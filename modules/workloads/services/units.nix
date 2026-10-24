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
          }
        );

      addressOf =
        service:
        "${lib.removeSuffix ".0/24" networks.${service.network}.subnet}.${toString service.address}";

      networkService = name: network: {
        name = networkUnit name;
        value = {
          description = "Create the ${name} workload network in rootful Podman";
          # The workload table and egress rules have to fence the bridge from its first packet.
          requires = [ "nftables.service" ];
          after = [
            "nftables.service"
            "workload-egress.service"
          ];
          path = [ config.virtualisation.podman.package ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
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
                ++ lib.optional (network.egress == "none") "--disable-dns"
                ++ [ name ]
              )
            }
          '';
        };
      };

      container = name: service: {
        name = containerName name;
        value = {
          inherit (service) image imageFile volumes;
          autoStart = service.autostart;
          networks = [ service.network ];
          extraOptions = [
            "--userns=auto"
            "--ip=${addressOf service}"
          ]
          # Otherwise Podman copies the host's loopback resolvers and appends public ones.
          ++ lib.optional (networks.${service.network}.egress == "none") "--dns=none";
        };
      };

      containerService =
        name: service:
        let
          unit = "${networkUnit service.network}.service";
        in
        {
          name = config.virtualisation.oci-containers.containers.${containerName name}.serviceName;
          value = {
            requires = [ unit ];
            after = [ unit ];
            # Stops the container in the same switch that recreates its network.
            restartTriggers = [ (specHash networks.${service.network}) ];
          };
        };

      ports = lib.concatMap (
        service: map (port: port // { address = addressOf service; }) service.ports
      ) (lib.attrValues services);

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
            ++ [
              {
                assertion = lib.allUnique (map (port: "${port.protocol}/${toString port.host}") ports);
                message = "workloads.services: two services publish the same host port";
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
