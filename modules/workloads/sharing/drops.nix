_:
let
  dropsModule =
    {
      config,
      lib,
      metaOwner,
      options,
      ...
    }:
    let
      inherit (lib) types;
      root = "/var/lib/workloads/shares";
      ownerDir = owner: "${root}/${owner}";

      dropOf = enable: name: drop: {
        enable = lib.mkDefault enable;
        hostPath = "${ownerDir drop.owner}/${name}";
      };

      guestModule =
        { name, config, ... }:
        {
          config.shares.drop = dropOf (config.trust == "trusted") name config.shares.drop;
        };

      serviceModule =
        { name, config, ... }:
        {
          config.shares.drop = dropOf false name config.shares.drop;
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

      directory = owner: {
        d = {
          mode = "0700";
          user = owner;
          inherit (config.users.users.${owner}) group;
        };
      };

      shared = lib.attrNames (
        lib.filterAttrs (_: same: lib.length same > 1) (lib.groupBy (drop: drop.hostPath) drops)
      );
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
            assertions = [
              {
                assertion = shared == [ ];
                message = "workloads: a guest and a service of one name share the drop ${lib.concatStringsSep ", " shared}";
              }
            ];

            # A guest can chmod its share root, never the owner directory above it.
            systemd.tmpfiles.settings.workloads-drops = {
              ${root}.d = {
                mode = "0755";
                user = "root";
                group = "root";
              };
            }
            // lib.listToAttrs (
              map (owner: lib.nameValuePair (ownerDir owner) (directory owner)) (
                lib.unique (map (drop: drop.owner) drops)
              )
            )
            // lib.listToAttrs (map (drop: lib.nameValuePair drop.hostPath (directory drop.owner)) drops);
          }

          # Home Manager manages only the metaOwner home, so other owners get no link.
          (lib.optionalAttrs (options ? home-manager) {
            home-manager.users = lib.mkIf (lib.any (drop: drop.owner == metaOwner.username) drops) {
              ${metaOwner.username} =
                { config, ... }:
                {
                  home.file.workloads.source = config.lib.file.mkOutOfStoreSymlink (ownerDir metaOwner.username);
                };
            };
          })
        ]
      );
    };
in
{
  flake.nixosModules."workloads-sharing" = dropsModule;
}
