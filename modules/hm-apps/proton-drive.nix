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

  Bootstrap and on-demand use:
    The proton-drive-sync CLI is installed whenever the protondrive remote is
    ready, independent of services.protonDriveSync.enable. Every direction
    (bisync, up, down) requires a one-time baseline so an unattended first run
    cannot wipe the destination: confirm the authoritative side holds the
    desired contents, then run `proton-drive-sync --resync` once. Timer-driven
    runs refuse to sync until that baseline marker exists instead of silently
    seeding (for bisync, --resync also lets the local side win conflicts).

    proton-drive-sync            # run the configured sync immediately
    proton-drive-sync --resync   # establish (or rebuild) the baseline

  Multi-host caveat:
    services.protonDriveSync.enable is off by default and should be enabled on
    at most one host per Proton account: rclone bisync keeps per-machine
    listings and assumes a single peer per side, so two hosts on independent
    timers race on listings and conflict resolution.
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
              # rclone sync mirrors local -> remote and deletes remote-only
              # files, so an unattended first run against a freshly created
              # empty local would wipe Proton. Gate the first run behind an
              # explicit --resync (after the operator confirms the local seed),
              # same as bisync; later timer runs proceed once the marker exists.
              if [ "$resync" -ne 1 ] && [ ! -e "$state_dir/initialized" ]; then
                echo "proton-drive-sync: no baseline; run 'proton-drive-sync --resync' once after confirming '$local_path' holds the desired seed (up mirrors local -> remote and deletes remote-only files)." >&2
                exit 1
              fi
              rclone sync "$local_path" "$remote" --create-empty-src-dirs "''${common[@]}" "''${extra[@]}"
              touch "$state_dir/initialized"
              ;;
            down)
              # rclone sync mirrors remote -> local and deletes local-only
              # files, so an unattended first run would clobber a local seed.
              # Same first-run gate as up/bisync.
              if [ "$resync" -ne 1 ] && [ ! -e "$state_dir/initialized" ]; then
                echo "proton-drive-sync: no baseline; run 'proton-drive-sync --resync' once after confirming '$remote' holds the desired contents (down mirrors remote -> local and deletes local-only files)." >&2
                exit 1
              fi
              rclone sync "$remote" "$local_path" --create-empty-src-dirs "''${common[@]}" "''${extra[@]}"
              touch "$state_dir/initialized"
              ;;
            bisync)
              if [ "$resync" -eq 1 ]; then
                echo "proton-drive-sync: building bisync baseline (--resync; local side wins conflicts)" >&2
                rclone bisync "$local_path" "$remote" --resync --create-empty-src-dirs --resilient "''${common[@]}" "''${extra[@]}"
                touch "$state_dir/initialized"
              elif [ ! -e "$state_dir/initialized" ]; then
                echo "proton-drive-sync: no bisync baseline; run 'proton-drive-sync --resync' once after confirming '$local_path' holds the desired seed contents." >&2
                exit 1
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
          default = false;
          description = ''
            Whether to run automatic Proton Drive syncing. Off by default even
            when the protondrive rclone remote is ready: enable this on at most
            one host per Proton account, since rclone bisync assumes a single
            peer per side and two hosts syncing against the same remote race on
            listings and conflict resolution.
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

      config = lib.mkMerge [
        # The CLI is the documented bootstrap/recovery path
        # (proton-drive-sync --resync), so it must exist while the timer is
        # still off; only the units are gated on cfg.enable.
        (lib.mkIf protondriveReady {
          home.packages = [ syncScript ];
        })

        (lib.mkIf cfg.enable {
          systemd.user.services.proton-drive-sync = {
            # No network-online.target dependency: the user manager has no
            # such target, so ordering against it is a no-op. OnBootSec plus
            # the periodic retry cover the offline-at-boot case.
            Unit.Description = "Proton Drive sync via rclone (${cfg.direction})";
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
            };
            Install.WantedBy = [ "timers.target" ];
          };
        })
      ];
    };
}
