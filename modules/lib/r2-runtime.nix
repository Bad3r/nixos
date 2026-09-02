{ lib, config, ... }:
let
  # The profile definitions are the source of truth for the producer's mount,
  # bisync, provisioning, and identity settings. The upstream unit names are
  # derived from each profile name, so an upstream naming change is asserted below.
  r2Mounts = {
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
  r2MountNames = lib.attrNames r2Mounts;
  r2MountServiceNames = map (name: "r2-mount-${name}") r2MountNames;
  r2BisyncServiceNames = map (name: "r2-bisync-${name}") r2MountNames;
  r2WriterServiceNames = r2MountServiceNames ++ r2BisyncServiceNames ++ [ "r2-restic-backup" ];
  r2ServiceNames = [ "r2-runtime-paths" ] ++ r2WriterServiceNames;
in
{
  flake.lib.nixos.r2 = {
    _serviceNames = r2ServiceNames;

    mkHostR2Module =
      {
        inputs,
        metaOwner,
        secretsRoot,
        policy,
      }:
      let
        mountGateFor =
          config.flake.lib.nixos._localMirrorsMountGate
            or (throw "modules/git/mirror-root.nix no longer exports flake.lib.nixos._localMirrorsMountGate");
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
          lib.optional (
            !externalFlakeEnabled
          ) "the host module passes enableExternalFlake = false to mkHostR2Module"
          ++ lib.optional (
            externalFlakeEnabled && !(externalNixosModuleEnabled && externalHomeModuleEnabled)
          ) "the r2-flake input exposes no nixosModules.default/homeManagerModules.default"
          ++ lib.optional (
            !policy.sopsRuntimeReady
          ) "the host module passes sopsRuntimeReady = false to mkHostR2Module"
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
          "${runtimeRoot}/r2"
          "${runtimeRoot}/r2/mount"
        ]
        ++ lib.concatMap (
          name:
          let
            mount = r2Mounts.${name};
          in
          [
            mount.mountPoint
            mount.localPath
          ]
        ) r2MountNames;
        missingWriterServiceNames = lib.filter (
          name: !(lib.hasAttrByPath [ "systemd" "services" name "serviceConfig" "ExecStart" ] config)
        ) r2WriterServiceNames;

        r2RuntimePathsModule =
          {
            config,
            lib,
            pkgs,
            utils,
            ...
          }:
          let
            # Empty on tpnix, which keeps /data on the root filesystem and so
            # has no mount to order against.
            mountGate = mountGateFor runtimeRoot config.fileSystems utils;
            mountAfter = mountGate.after;
            mountCondition = mountGate.unitConfig;
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
                  # One install invocation for every path: they share the same
                  # mode and owner, so a process per path is pure fork/exec
                  # overhead for an identical result.
                  ExecStart = "${pkgs.coreutils}/bin/install -d -m 0750 -o ${username} -g ${group} ${lib.escapeShellArgs runtimePaths}";
                };
              };
            }
            // lib.genAttrs r2WriterServiceNames (_: {
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

            assertions = [
              {
                assertion = missingWriterServiceNames == [ ];
                message = "r2 runtime: r2-flake service naming no longer matches the guarded writer set: ${lib.concatStringsSep ", " missingWriterServiceNames}";
              }
            ];

            services.r2-sync = {
              enable = true;
              credentialsFile = "/run/secrets/r2/credentials.env";
              accountIdFile = "/run/secrets/r2/account-id";

              mounts = r2Mounts;
            };

            services.r2-restic = {
              enable = true;
              credentialsFile = "/run/secrets/r2/credentials.env";
              accountIdFile = "/run/secrets/r2/account-id";
              passwordFile = "/run/secrets/r2/restic-password";
              bucket = "nix-r2-cf-backups-prod";
              paths = [ r2Mounts.workspace.localPath ];
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

            # Derive all writer settings from the profile names. A new profile
            # then receives the gate, identity, and bisync timeout together.
            systemd.services =
              lib.genAttrs r2MountServiceNames (_: {
                serviceConfig = {
                  User = username;
                  Group = group;
                };
              })
              // lib.genAttrs r2BisyncServiceNames (_: {
                serviceConfig = {
                  User = username;
                  Group = group;
                  # base unit sets TimeoutStartUSec=infinity; bound above bisync's own --max-lock=15m
                  TimeoutStartSec = "20m";
                };
              })
              // {
                "r2-restic-backup".serviceConfig = {
                  User = username;
                  Group = group;
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
  };
}
