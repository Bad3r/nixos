{ config, ... }:
let
  hostsRegistry = config.flake.lib.nixos.hosts or { };
  lanCidrs = config.flake.lib.nixos._firewallLocalNetworkCidrs;
  warpInterface = config.flake.lib.nixos._firewallMeshInterface;
  addressBlock = "172.16.0.0/16";
  # LAN, CGNAT (Mesh), link-local, and every workload subnet.
  privateCidrs = [
    "10.0.0.0/8"
    "100.64.0.0/10"
    "169.254.0.0/16"
    "172.16.0.0/12"
    "192.168.0.0/16"
  ];
  # warp-svc hardcodes its routing table number.
  warpTable = 65743;

  networksModule =
    {
      config,
      lib,
      pkgs,
      hostName,
      utils,
      ...
    }:
    let
      inherit (lib) types;
      networkIds = hostsRegistry.${hostName}.workloadNetworkIds or { };
      networks = lib.attrValues config.workloads.networks;
      nftSet = values: "{ ${lib.concatMapStringsSep ", " toString values} }";
      dnsPorts = network: lib.optional (network.egress == "warp") 53;
      tcpPorts = network: dnsPorts network ++ network.hostPorts.tcp;
      udpPorts = network: dnsPorts network ++ network.hostPorts.udp;

      inputRules =
        network:
        let
          dev = ''iifname "${network.bridge}"'';
          gatewayRule =
            proto: ports:
            lib.optional (
              ports != [ ]
            ) "${dev} ip daddr ${network.gateway} ${proto} dport ${nftSet ports} accept";
        in
        [ "${dev} ip daddr { ${network.gateway}, 255.255.255.255 } udp dport 67 accept" ]
        ++ gatewayRule "tcp" (tcpPorts network)
        ++ gatewayRule "udp" (udpPorts network)
        ++ [ "${dev} ip daddr ${network.gateway} icmp type echo-request accept" ];

      lanAccessRules = map (
        network: ''iifname "${network.bridge}" ip daddr { ${lib.concatStringsSep ", " lanCidrs} } accept''
      ) (lib.filter (network: network.lanAccess) networks);

      # 0.0.0.0 is a DHCP client without an address yet.
      antiSpoofRules = map (
        network: ''iifname "${network.bridge}" ip saddr != { ${network.subnet}, 0.0.0.0 } drop''
      ) networks;

      # A hairpin through the gateway would otherwise bypass workload-peers.
      sameBridgeRules = map (
        network: ''iifname "${network.bridge}" oifname "${network.bridge}" accept''
      ) (lib.filter (network: !network.isolatePeers) networks);

      isolatedBridges = map (network: ''"${network.bridge}"'') (
        lib.filter (network: network.isolatePeers) networks
      );

      lines = lib.concatStringsSep "\n";

      egressRules =
        network:
        let
          pref = offset: toString (31000 + 10 * network.id + offset);
          rule = offset: action: "rule add pref ${pref offset} iif ${network.bridge} ${action}";
        in
        # Main is consulted only for LAN destinations, so no route there can
        # carry guest traffic out the uplink.
        lib.optionals network.lanAccess (
          lib.imap0 (index: cidr: rule index "to ${cidr} lookup main") lanCidrs
        )
        ++ lib.optional (network.egress == "warp") (rule 5 "lookup ${toString warpTable}")
        ++ [ (rule 9 "unreachable") ];

      warpDevice = "${utils.escapeSystemdPath "/sys/subsystem/net/devices/${warpInterface}"}.device";

      networkModule =
        { name, config, ... }:
        {
          options = {
            id = lib.mkOption {
              type = types.ints.between 0 99;
              default =
                networkIds.${name}
                  or (throw "workloads.networks.${name}: add ${name} to workloadNetworkIds in modules/hosts/${hostName}/policy.nix");
              defaultText = lib.literalExpression "flake.lib.nixos.hosts.<host>.workloadNetworkIds.<name>";
              description = "Address registry index; the network takes the /24 at this index inside ${addressBlock} and the policy-routing preferences from 31000 + 10 * id.";
            };

            egress = lib.mkOption {
              type = types.enum [
                "warp"
                "none"
              ];
              default = "warp";
              description = ''
                Where forwarded guest traffic leaves the host. `warp` routes it
                through the Cloudflare WARP tunnel and fails closed while the
                tunnel is down; `none` gives the network no route and no DNS.
              '';
            };

            hostPorts = {
              tcp = lib.mkOption {
                type = types.listOf types.port;
                default = [ ];
                description = "TCP ports on the host that guests reach at the gateway address.";
              };
              udp = lib.mkOption {
                type = types.listOf types.port;
                default = [ ];
                description = "UDP ports on the host that guests reach at the gateway address.";
              };
            };

            lanAccess = lib.mkOption {
              type = types.bool;
              default = false;
              description = "Whether guests may open connections to the local network.";
            };

            isolatePeers = lib.mkOption {
              type = types.bool;
              default = false;
              description = "Whether to drop traffic between guests on the same bridge.";
            };

            bridge = lib.mkOption {
              type = types.strMatching "vn-[a-z0-9-]{1,12}";
              readOnly = true;
              default = "vn-${name}";
              defaultText = lib.literalExpression ''"vn-<name>"'';
              description = "Bridge interface the runtime creates for this network.";
            };

            subnet = lib.mkOption {
              type = types.str;
              readOnly = true;
              default = "172.16.${toString config.id}.0/24";
              defaultText = lib.literalExpression ''"172.16.<id>.0/24"'';
              description = "IPv4 subnet of the network.";
            };

            gateway = lib.mkOption {
              type = types.str;
              readOnly = true;
              default = "172.16.${toString config.id}.1";
              defaultText = lib.literalExpression ''"172.16.<id>.1"'';
              description = "Host address on the bridge.";
            };

            mtu = lib.mkOption {
              type = types.ints.positive;
              readOnly = true;
              # CloudflareWARP's 1300 less WireGuard's IPv4 overhead, so a nested tunnel fits.
              default = if config.egress == "warp" then 1240 else 1500;
              defaultText = lib.literalExpression ''if egress == "warp" then 1240 else 1500'';
              description = "MTU guests on the network use.";
            };
          };
        };
    in
    {
      options.workloads.networks = lib.mkOption {
        type = types.attrsOf (types.submodule networkModule);
        default = { };
        description = ''
          Workload networks: one bridge each, isolated from the host, the
          LAN, and each other except where an option opens a path.
        '';
      };

      config = lib.mkMerge [
        # An explicit 0 turns forwarding off again when a switch drops the last network.
        { boot.kernel.sysctl."net.ipv4.conf.all.forwarding" = lib.mkDefault false; }

        (lib.mkIf (networks != [ ]) {
          assertions = [
            {
              assertion = lib.allUnique (map (network: network.id) networks);
              message = "workloads.networks ids must be unique: ${
                lib.concatMapStringsSep ", " (network: "${network.bridge}=${toString network.id}") networks
              }";
            }
          ];

          boot.kernel.sysctl."net.ipv4.conf.all.forwarding" = true;

          programs.cloudflare-warp.extended.enable = lib.mkIf (lib.any (
            network: network.egress == "warp"
          ) networks) (lib.mkOverride 1050 true);

          networking.firewall.interfaces = lib.listToAttrs (
            map (network: {
              name = network.bridge;
              value = {
                allowedTCPPorts = tcpPorts network;
                allowedUDPPorts = [ 67 ] ++ udpPorts network;
              };
            }) networks
          );

          networking.nftables.tables = {
            workload = {
              family = "inet";
              # A drop here is final, so new traffic from a bridge never reaches
              # the global ports nixos-fw opens at priority filter.
              content = ''
                chain prerouting {
                  type filter hook prerouting priority raw; policy accept;
                  ${lines antiSpoofRules}
                }

                chain input {
                  type filter hook input priority filter - 1; policy accept;
                  iifname != "vn-*" accept
                  ct state vmap { established : accept, related : accept, invalid : drop }
                  ${lines (lib.concatMap inputRules networks)}
                  drop
                }

                chain forward {
                  type filter hook forward priority filter - 1; policy accept;
                  iifname != "vn-*" oifname != "vn-*" drop
                  ct state vmap { established : accept, related : accept, invalid : drop }
                  ${lines sameBridgeRules}
                  iifname != "vn-*" drop
                  oifname "vn-*" drop
                  ${lines lanAccessRules}
                  ip daddr { ${lib.concatStringsSep ", " privateCidrs} } drop
                }

                chain postrouting {
                  type nat hook postrouting priority srcnat; policy accept;
                  ip saddr ${addressBlock} oifname != "vn-*" masquerade
                }
              '';
            };

            workload-peers = {
              enable = isolatedBridges != [ ];
              family = "bridge";
              content = ''
                chain forward {
                  type filter hook forward priority filter; policy accept;
                  meta ibrname { ${lib.concatStringsSep ", " isolatedBridges} } drop
                }
              '';
            };
          };

          systemd.services.workload-egress = {
            description = "Policy routing for workload networks";
            # Not RemainAfterExit: an inactive unit reruns each time the tunnel
            # device appears and on every switch.
            wantedBy = [
              "multi-user.target"
              warpDevice
            ];
            # Every tunnel transition starts the unit.
            startLimitIntervalSec = 0;
            before = [ "network-pre.target" ];
            wants = [ "network-pre.target" ];
            path = [
              pkgs.gawk
              pkgs.iproute2
            ];
            serviceConfig.Type = "oneshot";
            # One batch swaps the band; WARP's own rule sits outside it. No
            # ExecStop, so the rules outlive the unit and warp stays closed.
            script = ''
              {
                ip rule show | awk -F: '$1 >= 31000 && $1 <= 31999 { print "rule del pref " $1 }'
                cat ${pkgs.writeText "workload-egress-rules" (lines (lib.concatMap egressRules networks) + "\n")}
              } | ip -batch -
            '';
          };
        })
      ];
    };
in
{
  flake.nixosModules."workloads-networks" = networksModule;
}
