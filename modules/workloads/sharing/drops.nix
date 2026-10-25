_:
let
  dropsModule =
    {
      config,
      lib,
      options,
      ...
    }:
    let
      inherit (lib) types;
      root = "/var/lib/workloads/shares";

      dropOf = enable: name: {
        enable = lib.mkDefault enable;
        hostPath = "${root}/${name}";
      };

      guestModule =
        { name, config, ... }:
        {
          config.shares.drop = dropOf (config.trust == "trusted") name;
        };

      serviceModule =
        { name, ... }:
        {
          config.shares.drop = dropOf false name;
        };

      enabledDrop =
        name: object:
        lib.optional (object.shares.drop.enable && (object.ensure or "present") == "present") {
          inherit name;
          inherit (object.shares.drop) hostPath owner;
        };

      drops =
        lib.concatLists (lib.mapAttrsToList enabledDrop config.workloads.guests)
        ++ lib.concatLists (lib.mapAttrsToList enabledDrop config.workloads.services);
    in
    {
      options.workloads = {
        guests = lib.mkOption {
          type = types.attrsOf (types.submodule guestModule);
        };

        services = lib.mkOption {
          type = types.attrsOf (types.submodule serviceModule);
        };
      };

      config = lib.mkIf (drops != [ ]) (
        lib.mkMerge [
          {
            systemd.tmpfiles.settings.workloads-drops = {
              ${root}.d = {
                mode = "0755";
                user = "root";
                group = "root";
              };
            }
            // lib.listToAttrs (
              map (
                drop:
                lib.nameValuePair drop.hostPath {
                  d = {
                    mode = "0700";
                    user = drop.owner;
                    inherit (config.users.users.${drop.owner}) group;
                  };
                }
              ) drops
            );
          }

          (lib.optionalAttrs (options ? home-manager) {
            home-manager.users = lib.mapAttrs (
              _: owned:
              { config, ... }:
              {
                home.file = lib.listToAttrs (
                  map (
                    drop:
                    lib.nameValuePair "workloads/${drop.name}" {
                      source = config.lib.file.mkOutOfStoreSymlink drop.hostPath;
                    }
                  ) owned
                );
              }
            ) (lib.groupBy (drop: drop.owner) drops);
          })
        ]
      );
    };
in
{
  flake.nixosModules."workloads-sharing" = dropsModule;
}
