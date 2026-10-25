_:
let
  # Marks a Podman network the module owns; the value is the hash of its spec.
  ownerLabel = "io.github.bad3r.nixos.workloads";

  # systemd's unused block between its container ranges and the foreign range.
  autoUsernsRange = {
    start = 1879048192;
    count = 268304384;
  };

  unitsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.workloads) networks services;
      podmanNetworks = lib.filterAttrs (_: network: network.podman.enable) networks;
      toml = pkgs.formats.toml { };

      containerName = name: "svc-${name}";
      networkUnit = name: "workloads-podman-net-${name}";

      # warp-svc's local resolvers; aardvark-dns would otherwise follow
      # /etc/resolv.conf and answer outside WARP while the tunnel is down.
      dnsServers =
        network:
        lib.optionals (network.egress == "warp") [
          "127.0.2.2"
          "127.0.2.3"
        ];

      specHash =
        network:
        builtins.hashString "sha256" (
          builtins.toJSON {
            inherit (network)
              bridge
              subnet
              gateway
              mtu
              ;
            dns = network.egress != "none";
            dnsServers = dnsServers network;
          }
        );

      addressOf =
        service:
        "${lib.removeSuffix ".0/24" networks.${service.network}.subnet}.${toString service.address}";

      ensureNetwork =
        name: network:
        pkgs.writeShellScript "workloads-podman-net-${name}" ''
          set -euo pipefail
          export PATH=${
            lib.makeBinPath [
              config.virtualisation.podman.package
              pkgs.iproute2
              pkgs.util-linux
            ]
          }
          # Network units and container starts run this concurrently.
          exec 9>/run/lock/workloads-podman-net-${name}.lock
          flock 9
          if podman network exists ${name}; then
            spec=$(podman network inspect --format '{{index .Labels "${ownerLabel}"}}' ${name})
            if [ -z "$spec" ]; then
              echo "Podman network ${name} exists without the ${ownerLabel} label; remove or rename it" >&2
              exit 1
            fi
            if [ "$spec" = ${specHash network} ]; then
              exit 0
            fi
            # Fails while a container is attached.
            podman network rm ${name}
          elif ip link show dev ${network.bridge} >/dev/null 2>&1; then
            # netavark would adopt the bridge and skip its route_localnet setup.
            echo "${network.bridge} exists but no labelled Podman network owns it; remove it first" >&2
            exit 1
          fi
          podman network create ${
            lib.escapeShellArgs (
              [
                "--label=${ownerLabel}=${specHash network}"
                "--interface-name=${network.bridge}"
                "--subnet=${network.subnet}"
                "--gateway=${network.gateway}"
                "--opt=mtu=${toString network.mtu}"
              ]
              ++ map (server: "--dns=${server}") (dnsServers network)
              ++ lib.optional (network.egress == "none") "--disable-dns"
              ++ [ name ]
            )
          }
        '';

      networkService = name: network: {
        name = networkUnit name;
        value = {
          description = "Create the ${name} workload network in rootful Podman";
          # The workload table and egress rules have to fence the bridge from its first packet.
          requires = [
            "nftables.service"
            "workload-egress.service"
          ];
          after = [
            "nftables.service"
            "workload-egress.service"
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = ensureNetwork name network;
          };
        };
      };

      enabledShares = service: lib.filterAttrs (_: share: share.enable) service.shares;

      ownerIds =
        share:
        let
          user = config.users.users.${share.owner} or { };
        in
        {
          uid = user.uid or null;
          gid = config.users.groups.${user.group or ""}.gid or null;
        };

      # `@` resolves the second id inside the container's own --userns=auto range.
      shareVolume =
        share:
        let
          ids = ownerIds share;
        in
        "${share.hostPath}:${share.mountPoint}:${lib.optionalString share.readOnly "ro,"}idmap=uids=@${toString ids.uid}-0-1;gids=@${toString ids.gid}-0-1";

      container = name: service: {
        name = containerName name;
        value = {
          inherit (service) image imageFile;
          volumes = service.volumes ++ lib.mapAttrsToList (_: shareVolume) (enabledShares service);
          autoStart = service.autostart;
          networks = [ service.network ];
          extraOptions = [
            "--userns=auto"
            "--ip=${addressOf service}"
            # The host's /etc/hosts carries Mesh names.
            "--hosts-file=none"
          ]
          # Otherwise Podman copies the host's loopback resolvers and appends public ones.
          ++ lib.optional (networks.${service.network}.egress == "none") "--dns=none";
        };
      };

      containerService =
        name: service:
        let
          unit = "${networkUnit service.network}.service";
          network = networks.${service.network};
        in
        {
          name = config.virtualisation.oci-containers.containers.${containerName name}.serviceName;
          value = {
            requires = [ unit ];
            after = [ unit ];
            # Stops the container in the same switch that recreates its network.
            restartTriggers = [ (specHash network) ];
            # The network unit never re-checks after its first run.
            serviceConfig.ExecStartPre = lib.mkBefore [ (ensureNetwork service.network network) ];
          };
        };

      ports = lib.concatMap (
        service: map (port: port // { address = addressOf service; }) service.ports
      ) (lib.attrValues services);

      # Services on an undeclared network already fail their own assertion.
      sharedAddresses = lib.filterAttrs (_: names: lib.length names > 1) (
        lib.groupBy (name: addressOf services.${name}) (
          lib.attrNames (lib.filterAttrs (_: service: podmanNetworks ? ${service.network}) services)
        )
      );

      dnatRules = map (
        port:
        "ip daddr 127.0.0.1 ${port.protocol} dport ${toString port.host} dnat ip to ${port.address}:${toString port.container}"
      ) ports;
    in
    {
      config = lib.mkMerge [
        {
          programs.podman.extended.enable = lib.mkIf (podmanNetworks != { } || services != { }) (
            lib.mkOverride 1050 true
          );
        }

        (lib.mkIf (podmanNetworks != { }) {
          assertions = lib.mapAttrsToList (name: network: {
            assertion = !(lib.attrByPath [ "libvirt" "enable" ] false network);
            message = "workloads.networks.${name}: libvirt and podman cannot both own bridge ${network.bridge}";
          }) podmanNetworks;

          # netavark's rules would duplicate the workload table's; inet workload fences the bridges.
          virtualisation.containers.containersConf.settings.network.firewall_driver = lib.mkForce "none";
          # Rootless networks live in their own namespace and keep netavark's firewall.
          environment.etc."containers/containers.rootless.conf".source =
            toml.generate "containers.rootless.conf"
              { network.firewall_driver = "nftables"; };

          systemd.services = lib.mapAttrs' networkService podmanNetworks;
        })

        (lib.mkIf (services != { }) {
          assertions =
            lib.mapAttrsToList (name: service: {
              assertion = podmanNetworks ? ${service.network};
              message = "workloads.services.${name}: network ${service.network} needs workloads.networks.${service.network}.podman.enable";
            }) services
            ++ lib.concatLists (
              lib.mapAttrsToList (
                name: service:
                lib.mapAttrsToList (
                  tag: share:
                  let
                    ids = ownerIds share;
                  in
                  {
                    # Mapped to 0, container root would create setuid- or setgid-root files on the host.
                    assertion = ids.uid != null && ids.uid != 0 && ids.gid != null && ids.gid != 0;
                    message = "workloads.services.${name}: shares.${tag}: owner ${share.owner} needs to be a declared non-root user with a fixed uid and a non-root primary group with a fixed gid";
                  }
                ) (enabledShares service)
              ) services
            )
            ++ [
              {
                assertion = lib.allUnique (map (port: "${port.protocol}/${toString port.host}") ports);
                message = "workloads.services: two services publish the same host port";
              }
              {
                assertion = sharedAddresses == { };
                message = "workloads.services: services share an address: ${
                  lib.concatStringsSep "; " (
                    lib.mapAttrsToList (
                      address: names: "${lib.concatStringsSep ", " names} on ${address}"
                    ) sharedAddresses
                  )
                }";
              }
            ];

          virtualisation.oci-containers = {
            backend = "podman";
            containers = lib.mapAttrs' container services;
          };

          systemd.services = lib.mapAttrs' containerService services;

          # --userns=auto draws container ids from the subordinate ranges of this user.
          users.users.containers = {
            isSystemUser = true;
            group = "containers";
            subUidRanges = [
              {
                startUid = autoUsernsRange.start;
                inherit (autoUsernsRange) count;
              }
            ];
            subGidRanges = [
              {
                startGid = autoUsernsRange.start;
                inherit (autoUsernsRange) count;
              }
            ];
          };
          users.groups.containers = { };
        })

        (lib.mkIf (ports != [ ]) {
          # netavark sets route_localnet on the bridge, so a packet rewritten
          # from 127.0.0.1 may leave through it.
          networking.nftables.tables.workload.content = lib.mkAfter ''
            chain services-output {
              type nat hook output priority dstnat; policy accept;
              ${lib.concatStringsSep "\n" dnatRules}
            }

            chain services-postrouting {
              type nat hook postrouting priority srcnat; policy accept;
              ip saddr 127.0.0.0/8 oifname "vn-*" masquerade
            }
          '';
        })
      ];
    };
in
{
  flake.nixosModules."workloads-services" = unitsModule;
}
