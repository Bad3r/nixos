{ lib, config, ... }:
{
  flake.lib.nixos.r2.mkHostR2Module =
    {
      inputs,
      metaOwner,
      secretsRoot,
      policy,
    }:
    let
      enclosingMountOf =
        config.flake.lib.nixos._localMirrorsEnclosingMount
          or (throw "modules/git/mirror-root.nix no longer exports flake.lib.nixos._localMirrorsEnclosingMount");
      externalFlakeEnabled = policy.enableExternalFlake;
      r2ConfigFile = secretsRoot + "/r2.yaml";
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
      # The runtime block sets options that only exist when the r2-flake
      # modules are importable, so it must not outrun the import predicates.
      runtimeEnabled =
        externalNixosModuleEnabled
        && externalHomeModuleEnabled
        && policy.sopsRuntimeReady
        && builtins.pathExists r2ConfigFile;

      # The warning names only the conditions actually unmet. A fixed string
      # listing every precondition sends the reader to check the ones already
      # satisfied, which is how a bare `enableExternalFlake = false` reads as a
      # missing secret or an unmounted volume.
      unmet =
        lib.optional (!externalFlakeEnabled) "the host policy sets enableExternalFlake = false"
        ++ lib.optional (
          externalFlakeEnabled && !(externalNixosModuleEnabled && externalHomeModuleEnabled)
        ) "the r2-flake input exposes no nixosModules.default/homeManagerModules.default"
        ++ lib.optional (!policy.sopsRuntimeReady) "the host policy sets sopsRuntimeReady = false"
        ++ lib.optional (!builtins.pathExists r2ConfigFile) "${toString r2ConfigFile} is missing";
    in
    { config, lib, ... }:
    let
      inherit (metaOwner) username;
      group = lib.attrByPath [ "users" "users" username "group" ] "users" config;

      # Everything the runtime provisions or writes lives under this root, so a
      # single enclosing mount covers the provisioner and every writer.
      runtimeRoot = "/data";
      runtimePaths = [
        "/data/r2"
        "/data/r2/mount"
        "/data/r2/mount/workspace"
        "/data/r2/mount/fonts"
        "/data/r2/mount/docs"
        "/data/r2/workspace"
        "/data/fonts"
        "/data/Docs"
      ];
      writerNames = [
        "r2-mount-workspace"
        "r2-bisync-workspace"
        "r2-mount-fonts"
        "r2-bisync-fonts"
        "r2-mount-docs"
        "r2-bisync-docs"
        "r2-restic-backup"
      ];

      r2RuntimePathsModule =
        {
          config,
          lib,
          pkgs,
          utils,
          ...
        }:
        let
          enclosingMount = enclosingMountOf runtimeRoot config.fileSystems;
          # Null on a host that keeps /data on the root filesystem (tpnix),
          # which stays unconditional rather than losing the runtime entirely.
          mountAfter = lib.optional (
            enclosingMount != null
          ) "${utils.escapeSystemdPath enclosingMount}.mount";
          mountCondition = lib.optionalAttrs (enclosingMount != null) {
            ConditionPathIsMountPoint = enclosingMount;
          };
        in
        {
          # A unit rather than systemd.tmpfiles.rules, for the reason
          # modules/git/mirror-root.nix documents: tmpfiles.d(5) runs
          # unconditionally and creates leading directories, so a boot without
          # the volume built this whole tree on the root filesystem and the
          # writers below then filled it there instead of failing. A nofail
          # mount is not ordered before local-fs.target, so tmpfiles could lose
          # that race with the volume present as well.
          systemd.services = {
            r2-runtime-paths = {
              description = "Provision the R2 runtime paths under ${runtimeRoot}";
              wantedBy = [ "multi-user.target" ];
              after = mountAfter;
              unitConfig = mountCondition;
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = map (
                  path: "${pkgs.coreutils}/bin/install -d -m 0750 -o ${username} -g ${group} ${path}"
                ) runtimePaths;
              };
            };
          }
          // lib.genAttrs writerNames (_: {
            # Each writer repeats the condition instead of leaning on the
            # provisioner: systemd counts a condition-skipped dependency as
            # satisfied, so requires alone would still let a writer start
            # against an absent volume. requires covers the other direction,
            # where provisioning ran and failed.
            after = [ "r2-runtime-paths.service" ] ++ mountAfter;
            requires = [ "r2-runtime-paths.service" ];
            unitConfig = mountCondition;
          });
        };
    in
    {
      imports =
        lib.optionals externalNixosModuleEnabled [
          inputs."r2-flake".nixosModules.default
        ]
        # Separate module because this one needs pkgs and utils. A module
        # carrying `imports` is applied while the module graph is still being
        # collected, before `_module.args` can answer for either, so naming
        # them as formals on the outer module aborts the whole evaluation.
        ++ lib.optional runtimeEnabled r2RuntimePathsModule;

      config = lib.mkMerge [
        (lib.mkIf externalHomeModuleEnabled {
          home-manager.sharedModules = lib.mkAfter [
            inputs."r2-flake".homeManagerModules.default
          ];
        })

        # optionalAttrs, not mkIf: these options are declared only by the
        # conditionally imported r2-flake modules, so the definitions must
        # vanish entirely when the modules are absent.
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
            # Upstream defaults this to true, which would register a second
            # writer for ~/.config/rclone/rclone.conf. That file is owned by
            # modules/hm-apps/rclone.nix while programs.rclone.extended.enable
            # is set (the common-host default); its assertion rejects the
            # colliding combination.
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
                # base unit sets TimeoutStartUSec=infinity; bound above bisync's own --max-lock=15m
                TimeoutStartSec = "20m";
              };
              "r2-mount-fonts".serviceConfig = {
                User = username;
                Group = group;
              };
              "r2-bisync-fonts".serviceConfig = {
                User = username;
                Group = group;
                # base unit sets TimeoutStartUSec=infinity; bound above bisync's own --max-lock=15m
                TimeoutStartSec = "20m";
              };
              "r2-mount-docs".serviceConfig = {
                User = username;
                Group = group;
              };
              "r2-bisync-docs".serviceConfig = {
                User = username;
                Group = group;
                # base unit sets TimeoutStartUSec=infinity; bound above bisync's own --max-lock=15m
                TimeoutStartSec = "20m";
              };
              "r2-restic-backup".serviceConfig = {
                User = username;
                Group = group;
              };
            };
          };
        })

        (lib.mkIf (!runtimeEnabled) {
          warnings = [
            "${policy.disabledReason or "R2 runtime disabled."} Unmet: ${lib.concatStringsSep "; " unmet}."
          ];
        })
      ];
    };
}
