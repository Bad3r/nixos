{ lib, ... }:
{
  flake.lib.nixos.r2.mkHostR2Module =
    {
      inputs,
      metaOwner,
      secretsRoot,
      policy,
    }:
    let
      externalFlakeEnabled = policy.enableExternalFlake;
      r2ConfigFile = "${secretsRoot}/r2.yaml";
      # Import the option surface independently from SOPS runtime readiness.
      # Secret readiness gates only the host's runtime assignments below.
      externalNixosModuleEnabled =
        externalFlakeEnabled
        && lib.hasAttrByPath [
          "r2-flake"
          "nixosModules"
          "default"
        ] inputs;
      externalHomeModuleEnabled =
        externalFlakeEnabled
        && lib.hasAttrByPath [
          "r2-flake"
          "homeManagerModules"
          "default"
        ] inputs;
      runtimeEnabled =
        externalFlakeEnabled && policy.sopsRuntimeReady && builtins.pathExists r2ConfigFile;
    in
    { config, lib, ... }:
    let
      inherit (metaOwner) username;
      group = lib.attrByPath [ "users" "users" username "group" ] "users" config;
    in
    {
      imports = lib.optionals externalNixosModuleEnabled [
        inputs."r2-flake".nixosModules.default
      ];

      config = lib.mkMerge [
        (lib.mkIf externalHomeModuleEnabled {
          home-manager.sharedModules = lib.mkAfter [
            inputs."r2-flake".homeManagerModules.default
          ];
        })

        (lib.optionalAttrs runtimeEnabled {
          # Allow non-root mounts to use `--allow-other`.
          programs.fuse.userAllowOther = true;

          services.r2-sync = {
            enable = true;
            credentialsFile = "/run/secrets/r2/credentials.env";
            accountIdFile = "/run/secrets/r2/account-id";

            mounts = {
              workspace = {
                bucket = "nix-r2-cf-r2e-files-prod";
                remotePrefix = "workspace";
                mountPoint = "/data/r2/mount/workspace";
                localPath = "/data/r2/workspace";
                syncInterval = "5m";
              };

              fonts = {
                bucket = "nix-r2-cf-r2e-files-prod";
                remotePrefix = "fonts";
                mountPoint = "/data/r2/mount/fonts";
                localPath = "/data/fonts";
                syncInterval = "30m";
              };

              docs = {
                bucket = "nix-r2-cf-r2e-files-prod";
                remotePrefix = "docs";
                mountPoint = "/data/r2/mount/docs";
                localPath = "/data/Docs";
                syncInterval = "5m";
              };
            };
          };

          services.r2-restic = {
            enable = true;
            credentialsFile = "/run/secrets/r2/credentials.env";
            accountIdFile = "/run/secrets/r2/account-id";
            passwordFile = "/run/secrets/r2/restic-password";
            bucket = "nix-r2-cf-backups-prod";
            paths = [ "/data/r2/workspace" ];
          };

          programs.git-annex-r2 = {
            enable = true;
            credentialsFile = "/run/secrets/r2/credentials.env";
          };

          # Provide `r2` in PATH for the real user.
          home-manager.users.${username}.programs.r2-cloud = {
            enable = true;
            accountIdFile = "/run/secrets/r2/account-id";
            credentialsFile = "/run/secrets/r2/credentials.env";
            explorerEnvFile = "/run/secrets/r2/explorer.env";
            enableRcloneRemote = false;
          };

          systemd = {
            # Run operational services as the real user so /data/r2/* stays user-owned.
            services = {
              "r2-mount-workspace".serviceConfig = {
                User = username;
                Group = group;
              };
              "r2-bisync-workspace".serviceConfig = {
                User = username;
                Group = group;
              };
              "r2-mount-fonts".serviceConfig = {
                User = username;
                Group = group;
              };
              "r2-bisync-fonts".serviceConfig = {
                User = username;
                Group = group;
              };
              "r2-mount-docs".serviceConfig = {
                User = username;
                Group = group;
              };
              "r2-bisync-docs".serviceConfig = {
                User = username;
                Group = group;
              };
              "r2-restic-backup".serviceConfig = {
                User = username;
                Group = group;
              };
            };

            # Ensure paths exist (and are user-owned) before services start.
            tmpfiles.rules = [
              "d /data/r2 0750 ${username} ${group} - -"
              "d /data/r2/mount 0750 ${username} ${group} - -"
              "d /data/r2/mount/workspace 0750 ${username} ${group} - -"
              "d /data/r2/mount/fonts 0750 ${username} ${group} - -"
              "d /data/r2/mount/docs 0750 ${username} ${group} - -"
              "d /data/r2/workspace 0750 ${username} ${group} - -"
              "d /data/fonts 0750 ${username} ${group} - -"
              "d /data/Docs 0750 ${username} ${group} - -"
            ];
          };
        })

        (lib.optionalAttrs (!runtimeEnabled) {
          warnings = [ (policy.disabledReason or "R2 runtime disabled.") ];
        })
      ];
    };
}
