_:
let
  namesModule =
    { config, lib, ... }:
    let
      inherit (lib) types;
      cfg = config.workloads;
      hostnames = name: [
        name
        "${name}.vm"
      ];
      ipv4 = types.strMatching "(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])(\\.(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])){3}";

      nameModule =
        { config, ... }:
        {
          options = {
            address = lib.mkOption {
              type = ipv4;
              description = "IPv4 address the host resolves the name to.";
            };

            kind = lib.mkOption {
              type = types.enum [
                "guest"
                "service"
              ];
              description = "Kind of object the name belongs to, the prefix of its link and grant targets.";
            };

            network = lib.mkOption {
              type = types.str;
              description = "`workloads.networks` entry the address lies in.";
            };

            addresses = lib.mkOption {
              type = types.attrsOf ipv4;
              default.${config.network} = config.address;
              defaultText = lib.literalExpression "{ \${network} = address; }";
              description = "Address on each network the object sits on; a network's resolver answers with its own entry, else with `address`.";
            };
          };
        };

      networkModule =
        { name, config, ... }:
        {
          options = {
            resolve = lib.mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = ''
                Guest names from `workloads.names` whose `<name>` and
                `<name>.vm` the network's dnsmasq answers. A `none` network runs
                no resolver and aardvark-dns on a Podman network serves only its
                own containers, so their lists stay empty.
              '';
            };

            dnsHosts = lib.mkOption {
              type = types.attrsOf (types.listOf types.str);
              readOnly = true;
              default = lib.optionalAttrs (config.egress != "none") (
                lib.zipAttrsWith (_: lib.concatLists) (
                  [ { ${config.gateway} = [ "host.vm" ]; } ]
                  ++ map (
                    entry:
                    let
                      target = cfg.names.${entry};
                    in
                    {
                      ${target.addresses.${name} or target.address} = hostnames entry;
                    }
                  ) (lib.filter (entry: cfg.names ? ${entry}) (lib.unique config.resolve))
                )
              );
              defaultText = lib.literalExpression ''{ ''${gateway} = [ "host.vm" ]; <address> = [ "<name>" "<name>.vm" ]; }'';
              description = "Host records the network's resolver serves, hostnames by address.";
            };
          };
        };

      # A guest on several networks takes the address of its first interface.
      guestNames = lib.mapAttrs (
        _: guest:
        let
          nic = lib.head (lib.attrNames guest.interfaces);
        in
        {
          address = guest.address.${nic};
          kind = "guest";
          inherit (guest.interfaces.${nic}) network;
          addresses = lib.mapAttrs' (
            nic: interface: lib.nameValuePair interface.network guest.address.${nic}
          ) guest.interfaces;
        }
      ) (lib.filterAttrs (_: guest: guest.ensure == "present" && guest.interfaces != { }) cfg.guests);

      # A service on any other network fails the services module's own assertion.
      serviceNames =
        lib.mapAttrs
          (_: service: {
            address = "${
              lib.removeSuffix ".0/24" cfg.networks.${service.network}.subnet
            }.${toString service.address}";
            kind = "service";
            inherit (service) network;
          })
          (lib.filterAttrs (_: service: cfg.networks.${service.network}.podman.enable or false) cfg.services);

      namesFile = builtins.toJSON {
        names = lib.mapAttrs (name: entry: entry // { hostnames = hostnames name; }) cfg.names;
        networks = lib.mapAttrs (_: network: network.dnsHosts) (
          lib.filterAttrs (_: network: network.libvirt.enable && network.dnsHosts != { }) cfg.networks
        );
      };
    in
    {
      options.workloads = {
        names = lib.mkOption {
          type = types.attrsOf (types.submodule nameModule);
          default = { };
          description = ''
            Declared workload objects by name. The host resolves each as
            `<name>` and `<name>.vm`; a libvirt network's `resolve` list makes
            its guests resolve guest names too. Every present guest with an
            interface and every declared service adds itself.
          '';
        };

        networks = lib.mkOption {
          type = types.attrsOf (types.submodule networkModule);
        };
      };

      config = {
        workloads.names = lib.mkMerge [
          guestNames
          serviceNames
        ];

        assertions =
          lib.concatLists (
            lib.mapAttrsToList (
              networkName: network:
              [
                {
                  assertion = network.egress != "none" || network.resolve == [ ];
                  message = "workloads.networks.${networkName}.resolve: a none network runs no resolver";
                }
                {
                  assertion = !network.podman.enable || network.resolve == [ ];
                  message = "workloads.networks.${networkName}.resolve: aardvark-dns on a Podman network serves only its own containers";
                }
              ]
              ++ map (name: {
                assertion = cfg.names ? ${name};
                message = "workloads.networks.${networkName}.resolve: ${name} is not a workloads.names entry";
              }) network.resolve
              # The forward chain drops traffic between bridges, so the name would lead nowhere.
              ++ map (name: {
                assertion = (cfg.names.${name}.kind or null) != "service";
                message = "workloads.networks.${networkName}.resolve: ${name} is a service, which guests on ${networkName} cannot reach";
              }) network.resolve
            ) cfg.networks
          )
          ++ lib.concatLists (
            lib.mapAttrsToList (name: entry: [
              {
                # A dot or `host` would duplicate another record, which libvirt's live updates refuse.
                assertion = builtins.match "[a-z0-9][a-z0-9-]*" name != null && name != "host";
                message = "workloads.names.${name}: names match [a-z0-9][a-z0-9-]* and `host` is reserved for the gateway";
              }
              {
                assertion = lib.all (network: cfg.networks ? ${network}) (
                  [ entry.network ] ++ lib.attrNames entry.addresses
                );
                message = "workloads.names.${name}: network and addresses must name workloads.networks entries";
              }
            ]) cfg.names
          );

        networking.hosts = lib.mkMerge (
          lib.mapAttrsToList (name: entry: { ${entry.address} = hostnames name; }) cfg.names
        );

        programs.workloads.extended.enable = lib.mkIf (cfg.names != { }) (lib.mkOverride 1050 true);

        environment.etc."workloads/names.json" = lib.mkIf config.programs.workloads.extended.enable {
          text = namesFile;
        };
      };
    };
in
{
  flake.nixosModules."workloads-names" = namesModule;
}
