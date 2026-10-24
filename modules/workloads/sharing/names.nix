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

      nameModule = {
        options = {
          address = lib.mkOption {
            type = types.str;
            description = "IPv4 address the name resolves to.";
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
        };
      };

      networkModule =
        { config, ... }:
        {
          options = {
            resolve = lib.mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = ''
                `workloads.names` entries whose `<name>` and `<name>.vm` the
                network's resolver answers. A `none` network runs no resolver,
                so it answers none of them.
              '';
            };

            dnsHosts = lib.mkOption {
              type = types.attrsOf (types.listOf types.str);
              readOnly = true;
              default = lib.optionalAttrs (config.egress != "none") (
                lib.zipAttrsWith (_: lib.concatLists) (
                  [ { ${config.gateway} = [ "host.vm" ]; } ]
                  ++ map (name: { ${cfg.names.${name}.address} = hostnames name; }) (
                    lib.filter (name: cfg.names ? ${name}) (lib.unique config.resolve)
                  )
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
        }
      ) (lib.filterAttrs (_: guest: guest.ensure == "present" && guest.interfaces != { }) cfg.guests);

      namesFile = builtins.toJSON {
        names = lib.mapAttrs (name: entry: entry // { hostnames = hostnames name; }) cfg.names;
        networks = lib.mapAttrs (_: network: network.dnsHosts) (
          lib.filterAttrs (_: network: network.dnsHosts != { }) cfg.networks
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
            `<name>` and `<name>.vm`; a network's `resolve` list makes its
            guests resolve them too. Every present guest with an interface
            adds itself.
          '';
        };

        networks = lib.mkOption {
          type = types.attrsOf (types.submodule networkModule);
        };
      };

      config = {
        workloads.names = guestNames;

        assertions = lib.concatLists (
          lib.mapAttrsToList (
            networkName: network:
            map (name: {
              assertion = cfg.names ? ${name};
              message = "workloads.networks.${networkName}.resolve: ${name} is not a workloads.names entry";
            }) network.resolve
          ) cfg.networks
        );

        networking.hosts = lib.mkMerge (
          lib.mapAttrsToList (name: entry: { ${entry.address} = hostnames name; }) cfg.names
        );

        # The CLI's one verb lists declared names; live sandboxes alone have `sbx list`.
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
