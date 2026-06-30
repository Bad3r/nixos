/*
  Feature: Proton Drive sync (rclone protondrive backend)
  Backend docs: https://rclone.org/protondrive/
  Repository: https://github.com/rclone/rclone (backend/protondrive)

  Summary:
    * Drives an automatic, periodic Proton Drive sync from a systemd user timer
      plus an on-demand `proton-drive-sync` command for forcing a sync now.
    * The `[protondrive]` rclone remote itself is rendered by the rclone home
      module (modules/hm-apps/rclone.nix) from the SOPS secret
      secrets/rclone_protondrive.env; this module only orchestrates syncing.

  Status caveat:
    The protondrive backend is reverse-engineered (third-party Proton-API-Bridge)
    and officially Beta. Treat Proton Drive as a secondary copy, not the only copy
    of important data. enable_caching is forced off on the remote because Proton's
    change-event system is unimplemented.

  Activation prerequisites (one-time, cannot be automated, see CLAUDE.md flow):
    1. Log into Proton Drive in a browser once so account encryption keys exist.
    2. `rclone obscure '<login-password>'` (and the same for the TOTP secret and,
       on two-password accounts, the mailbox password).
    3. `sops secrets/rclone_protondrive.env` and store:
         PROTONDRIVE_USERNAME=you@proton.me
         PROTONDRIVE_PASSWORD=<obscured>
         PROTONDRIVE_OTP_SECRET_KEY=<obscured>      # only if 2FA is enabled
         PROTONDRIVE_MAILBOX_PASSWORD=<obscured>    # only on two-password accounts

  Force a sync on demand:
    proton-drive-sync            # run the configured sync immediately
    proton-drive-sync --resync   # rebuild the bisync baseline (recovery)
*/

_: {
  flake.homeManagerModules.apps.proton-drive =
    {
      osConfig,
      config,
      lib,
      pkgs,
      secretsRoot,
      ...
    }:
    let
      rcloneEnabled = lib.attrByPath [ "programs" "rclone" "extended" "enable" ] false osConfig;
      repoSecretsEnabled = lib.attrByPath [ "security" "repoSecrets" "enable" ] true osConfig;
      protondriveSecretFile = "${secretsRoot}/rclone_protondrive.env";
      protondriveSecretExists = builtins.pathExists protondriveSecretFile;
      protondriveEnvPath = lib.attrByPath [
        "sops"
        "secrets"
        "rclone/protondrive-env"
        "path"
      ] null osConfig;
      protondriveReady =
        rcloneEnabled && protondriveSecretExists && repoSecretsEnabled && protondriveEnvPath != null;

      cfg = config.services.protonDriveSync;
      rclonePackage = lib.attrByPath [ "programs" "rclone" "package" ] pkgs.rclone config;

      syncScript = pkgs.writeShellApplication {
        name = "proton-drive-sync";
        runtimeInputs = [
          rclonePackage
          pkgs.coreutils
        ];
        text = ''
          local_path=''${PROTON_DRIVE_LOCAL:-${cfg.localPath}}
          remote=''${PROTON_DRIVE_REMOTE:-${cfg.remote}}
          direction=''${PROTON_DRIVE_DIRECTION:-${cfg.direction}}
          state_dir=''${XDG_STATE_HOME:-$HOME/.local/state}/proton-drive-sync
          mkdir -p "$state_dir" "$local_path"

          resync=0
          for arg in "$@"; do
            case "$arg" in
              --resync | --force-resync) resync=1 ;;
              *)
                echo "proton-drive-sync: unknown argument: $arg" >&2
                exit 2
                ;;
            esac
          done

          extra=(${lib.escapeShellArgs cfg.extraArgs})
          common=(--protondrive-enable-caching=false --transfers=4 --checkers=8 --log-level INFO)

          case "$direction" in
            up)
              rclone sync "$local_path" "$remote" --create-empty-src-dirs "''${common[@]}" "''${extra[@]}"
              ;;
            down)
              rclone sync "$remote" "$local_path" --create-empty-src-dirs "''${common[@]}" "''${extra[@]}"
              ;;
            bisync)
              if [ "$resync" -eq 1 ] || [ ! -e "$state_dir/initialized" ]; then
                echo "proton-drive-sync: building initial bisync baseline (--resync)" >&2
                rclone bisync "$local_path" "$remote" --resync --create-empty-src-dirs --resilient "''${common[@]}" "''${extra[@]}"
                touch "$state_dir/initialized"
              else
                rclone bisync "$local_path" "$remote" --create-empty-src-dirs --resilient --conflict-resolve=newer --max-delete=25 "''${common[@]}" "''${extra[@]}"
              fi
              ;;
            *)
              echo "proton-drive-sync: unknown direction '$direction' (want bisync|up|down)" >&2
              exit 1
              ;;
          esac
        '';
      };
    in
    {
      options.services.protonDriveSync = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = protondriveReady;
          description = ''
            Whether to run automatic Proton Drive syncing. Defaults to true once
            the protondrive rclone remote is ready (rclone enabled, the SOPS
            secret present, and repo secrets active on the host).
          '';
        };

        localPath = lib.mkOption {
          type = lib.types.str;
          default = "${config.home.homeDirectory}/ProtonDrive";
          description = "Local directory kept in sync with Proton Drive.";
        };

        remote = lib.mkOption {
          type = lib.types.str;
          default = "protondrive:";
          description = "rclone remote (and optional path) to sync against.";
        };

        direction = lib.mkOption {
          type = lib.types.enum [
            "bisync"
            "up"
            "down"
          ];
          default = "bisync";
          description = ''
            Sync direction: "bisync" (two-way, Dropbox-like), "up" (local mirrors
            to Proton, safest), or "down" (Proton mirrors to local). One-way "up"
            and "down" use `rclone sync`, which deletes extra files on the
            destination to make it match the source.
          '';
        };

        interval = lib.mkOption {
          type = lib.types.str;
          default = "10m";
          example = "1h";
          description = "systemd time span between automatic syncs (OnUnitActiveSec).";
        };

        extraArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "--bwlimit=2M" ];
          description = "Extra arguments appended to every rclone invocation.";
        };
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ syncScript ];

        systemd.user.services.proton-drive-sync = {
          Unit = {
            Description = "Proton Drive sync via rclone (${cfg.direction})";
            After = [ "network-online.target" ];
            Wants = [ "network-online.target" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = lib.getExe syncScript;
          };
        };

        systemd.user.timers.proton-drive-sync = {
          Unit.Description = "Periodic Proton Drive sync (every ${cfg.interval})";
          Timer = {
            OnBootSec = "2m";
            OnUnitActiveSec = cfg.interval;
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
}
