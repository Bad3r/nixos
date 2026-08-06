/*
  Feature: Proton Drive sync (rclone protondrive backend)
  Backend docs: https://rclone.org/protondrive/
  Repository: https://github.com/rclone/rclone (backend/protondrive)

  Summary:
    * Drives an automatic, periodic Proton Drive sync from a systemd user timer
      plus an on-demand `proton-drive-sync` command for forcing a sync now.
    * The `[protondrive]` rclone remote itself is rendered by the rclone home
      module (modules/hm-apps/rclone.nix) from either the SOPS secret
      secrets/rclone_protondrive.env or configured 1Password references; this
      module only orchestrates syncing.

  Status caveat:
    The protondrive backend is reverse-engineered (third-party Proton-API-Bridge)
    and officially Beta. Treat Proton Drive as a secondary copy, not the only copy
    of important data. enable_caching is forced off on the remote because Proton's
    change-event system is unimplemented.

  Authentication prerequisites (one-time, cannot be automated):
    1. Log into Proton Drive in a browser once so account encryption keys exist.
    2. Enable `programs.rclone.extended.enable` and
       `programs.rclone.extended.protonDrive.enable`. Hosts in the hosts-common
       aggregate inherit those, `programs."1password-cli".extended`, and the
       four vault references at that aggregate's mkOverride 1100 baseline
       (modules/hosts/common/apps-enable.nix and
       modules/hosts/common/rclone-protondrive-1password.nix), which a per-host
       file overrides at 1000. Any other host supplies them itself: all four
       `onePassword.*Ref` options default to "", and usernameRef and passwordRef
       must be set.
    3. To use the SOPS fallback, set `authSource = "sops"` and obscure and store:
         PROTONDRIVE_USERNAME=you@proton.me
         PROTONDRIVE_PASSWORD=<obscured>
         PROTONDRIVE_OTP_SECRET_KEY=<obscured>      # only if 2FA is enabled
         PROTONDRIVE_MAILBOX_PASSWORD=<obscured>    # only on two-password accounts
    4. For the 1Password source, the desktop app must be running and unlocked
       with CLI integration turned on: activation resolves the references
       through the setgid `op` wrapper from `programs._1password`, and the app
       authorizes that call by its onepassword-cli group. usernameRef and
       passwordRef are mandatory; otpRef and mailboxPasswordRef may be left ""
       (only if 2FA is enabled / only on two-password accounts, same as the
       SOPS fields above). Leaving a ref empty is how an account opts out, so a
       ref that is set must resolve to a non-empty value; a blank field fails
       activation rather than rendering a remote that cannot work. The OTP
       reference must return the stable seed, either as an otpauth:// URI
       carrying `secret=` or as the bare base32 seed 1Password stores when the
       operator pastes one; the module extracts and obscures it, and requires
       at least the 16 base32 characters of an 80-bit seed. Omit
       `?attribute=otp` in either shape: it renders the changing six-digit
       code, which the module rejects rather than storing.
       Proton passkeys remain browser-only because the rclone backend logs in
       through the Proton API with username, password, mailbox password, and 2FA.

  Bootstrap and on-demand use:
    The proton-drive-sync CLI is installed whenever the protondrive remote is
    ready, independent of services.protonDriveSync.enable. Every direction
    (bisync, up, down) requires a one-time baseline so an unattended first run
    cannot wipe the destination: confirm the authoritative side holds the
    desired contents, then run `proton-drive-sync --resync` once. Timer-driven
    runs refuse to sync until that tuple's baseline marker exists instead of silently
    seeding (for bisync, --resync also lets the local side win conflicts).
    Normal one-way runs refuse an empty source and pass --max-delete=25 as an
    absolute 25-file deletion cap; --resync skips the cap after the operator
    confirms a nonempty source unless the previous one-way run hit exit 7. After
    that abort, --resync retains the cap and --force-resync is required to
    bypass it; --force-resync also permits an empty source. Normal bisync runs
    pass the same value as rclone's 25-percent deletion check; bisync --resync
    establishes the initial baseline without that check. A tripped bisync safety
    check leaves both sides untouched and carries no --resync lockout, so the run
    latches the same tuple instead of recomputing the abort from a full listing
    every interval; --force releases the latch and propagates the deletions after
    confirming a nonempty local source, and --resync releases it by rebuilding
    the baseline as a superset of both sides. Bisync listings live under this
    module's state directory beside the tuple marker, rooted at xdg.stateHome so
    the timer and an interactive shell resolve the same path.

    Per-invocation overrides:
      PROTON_DRIVE_LOCAL=/path proton-drive-sync
      PROTON_DRIVE_REMOTE=protondrive:Folder proton-drive-sync
      PROTON_DRIVE_DIRECTION=up proton-drive-sync
    These values are part of the baseline tuple, so changing one requires
    another explicit --resync. The timer unit clears all three
    (UnsetEnvironment=), so they affect interactive runs only: a scheduled fire
    always syncs the configured direction, path and remote, whatever the user
    manager's environment holds.

    proton-drive-sync            # run the configured sync immediately
    proton-drive-sync --resync   # establish (or rebuild) a nonempty baseline
    proton-drive-sync --force-resync # override the abort cap or permit an empty source
    proton-drive-sync --force    # release a latched bisync safety abort after confirming the local source

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
      protondriveSecretFile = secretsRoot + "/rclone_protondrive.env";
      protondriveSecretExists = builtins.pathExists protondriveSecretFile;
      protondriveEnvPath = lib.attrByPath [
        "sops"
        "secrets"
        "rclone/protondrive-env"
        "path"
      ] null osConfig;
      protondriveAuth =
        lib.attrByPath
          [
            "programs"
            "rclone"
            "extended"
            "protonDrive"
          ]
          {
            enable = false;
            authSource = "sops";
            onePassword = {
              usernameRef = "";
              passwordRef = "";
              otpRef = "";
              mailboxPasswordRef = "";
            };
          }
          osConfig;
      protondriveOnePassword = protondriveAuth.onePassword or { };
      # otp_secret_key and mailbox_password are per-account optional (2FA /
      # two-password accounts only), so an empty ref opts out instead of
      # failing readiness; a non-empty ref still must be an op:// reference.
      protondriveOptionalRefValid = ref: ref == "" || lib.hasPrefix "op://" ref;
      protondriveOnePasswordReady =
        protondriveAuth.enable
        && protondriveAuth.authSource == "onePassword"
        && lib.hasPrefix "op://" (protondriveOnePassword.usernameRef or "")
        && lib.hasPrefix "op://" (protondriveOnePassword.passwordRef or "")
        && protondriveOptionalRefValid (protondriveOnePassword.otpRef or "")
        && protondriveOptionalRefValid (protondriveOnePassword.mailboxPasswordRef or "");
      protondriveReady =
        rcloneEnabled
        && (
          protondriveOnePasswordReady
          || (
            protondriveAuth.enable
            && protondriveAuth.authSource == "sops"
            && protondriveSecretExists
            && repoSecretsEnabled
            && protondriveEnvPath != null
          )
        );

      cfg = config.services.protonDriveSync;
      rclonePackage = lib.attrByPath [ "programs" "rclone" "package" ] pkgs.rclone config;

      # extraArgs is appended last on every invocation and rclone's parser takes
      # the last occurrence of a flag, so an extraArg silently replaces the same
      # flag this module passes (verified against rclone 1.74.4:
      # `--max-delete=25 --max-delete=0` refuses the deletes). Two classes are
      # refused, both because the override is invisible in the sync's own output.
      #
      # Log routing, because run_bisync reads the run's own stderr to detect a
      # safety abort: --log-file and --syslog write elsewhere
      # (rclone fs/log/log.go), a --log-level under ERROR drops the record,
      # --log-format nolevel and --use-json-log strip the level prefix, and
      # --log-systemd does both (fs/log/systemd_unix.go startSystemdLog sets a
      # journald output and logFormatNoLevel). Auto-detection of a journal
      # stream is not a hole: run_bisync pipes rclone into tee, and
      # journal.StderrIsJournalStream stats fd 2, which is that pipe.
      #
      # Safety and mode, because each defeats a flag this module passes to hold
      # deletions back or to keep the baseline honest: --force skips both bisync
      # safety checks outright (cmd/bisync/operations.go guards each with
      # `if !opt.Force`), --max-delete replaces the cap, --conflict-loser=delete
      # drops the losing copy of every conflict, --dry-run leaves --resync
      # writing only `-dry` listings while the branch still records a baseline,
      # and --resync / --resync-mode turn a scheduled fire into a superset merge.
      # --ignore-errors lifts the one guard --max-delete cannot express: rclone
      # withholds destination deletes from a run that hit errors
      # (fs/sync/sync.go returns fs.ErrorNotDeleting under
      # `if accounting.Stats(ctx).Errored() && !s.ci.IgnoreErrors`), so against a
      # Beta backend a partial listing failure would delete rather than abort.
      #
      # --protondrive-enable-caching belongs to the same class, and the command
      # line is its sole authority rather than a reinforcement: fs/configmap.go
      # ConfigMap registers set flag values at PriorityNormal and the config
      # file at PriorityConfig, so an extraArg beats both the flag in common and
      # the enable_caching = false the rclone module writes into the stanza.
      # Caching stays off because Proton's change-event system is unimplemented,
      # so a stale metadata cache feeds bisync's delta computation directly.
      # --config and --workdir are the same class by a longer route, through the
      # tuple key rather than a deletion: the key is direction/local/remote, so
      # neither appears in it. A replacement --config that also defines
      # protondrive: reuses this account's baseline and latch against another
      # account's tree, and --workdir moves the bisync listings without moving
      # the $marker under state_dir that claims they exist, so pointing it at
      # /tmp (a tmpfs cleared on boot on this fleet) survives one reboot as a
      # baseline with nothing behind it: the unlatchable repeat --dry-run is
      # rejected for, reached with no intent to disable anything.
      #
      # --conflict-resolve and --resilient close the same set: the first is the
      # other half of the decision --conflict-loser governs, and --resilient is
      # a bool, so --resilient=false reinstates bisync's -err listing rename on
      # a retryable critical error (cmd/bisync/operations.go skips it only under
      # `b.retryable && b.opt.Resilient && !b.opt.Resync`), turning the
      # offline-at-boot retry the unit relies on into that same repeat.
      # --create-empty-src-dirs decides whether an empty source directory is
      # mirrored at all, and it is on all four invocations, so flipping it
      # changes what the bisync listings describe from one fire to the next.
      #
      # The invariant is that every flag the script passes is either here or
      # deliberately tunable (--transfers, --checkers, and --max-depth on the
      # down probe, which extra never reaches). The check reads the stub's
      # recorded argv and fails on any flag covered by neither, because stating
      # this in a comment is how --create-empty-src-dirs stayed outside both
      # lists while four rounds patched the ones next to it.
      rejectedFlags = [
        "--config"
        "--conflict-loser"
        "--conflict-resolve"
        "--create-empty-src-dirs"
        "--dry-run"
        "--force"
        "--ignore-errors"
        "--log-file"
        "--log-format"
        "--log-level"
        "--log-systemd"
        "--max-delete"
        "--protondrive-enable-caching"
        "--resilient"
        "--resync"
        "--resync-mode"
        "--syslog"
        "--use-json-log"
        "--workdir"
      ];
      # Short options cluster, so they cannot be matched flag by flag: `-nv` is
      # --dry-run plus --verbose, and bisync gives --resync the shorthand `-1`.
      # Every rejected flag has a long form, so require it rather than parse
      # clusters here. The first character must be an option character, not just
      # a non-dash: an rclone exclude rule is written `- *.partial`, which is a
      # value rather than a flag and has no long form to demand.
      isShortOption = arg: builtins.match "-[A-Za-z0-9].*" arg != null;
      rejectedArgs = lib.filter (
        arg: isShortOption arg || lib.any (flag: arg == flag || lib.hasPrefix "${flag}=" arg) rejectedFlags
      ) cfg.extraArgs;

      syncScript = pkgs.writeShellApplication {
        name = "proton-drive-sync";
        runtimeInputs = [
          rclonePackage
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnugrep
        ];
        text = ''
          # The defaults are single-quoted shell literals so metacharacters
          # in configured paths and remotes remain data, not shell syntax.
          # shellcheck disable=SC2016
          local_path=''${PROTON_DRIVE_LOCAL:-${lib.escapeShellArg cfg.localPath}}
          # shellcheck disable=SC2016
          remote=''${PROTON_DRIVE_REMOTE:-${lib.escapeShellArg cfg.remote}}
          # shellcheck disable=SC2016
          direction=''${PROTON_DRIVE_DIRECTION:-${lib.escapeShellArg cfg.direction}}
          # Pinned at eval time like the rclone config below: the systemd user
          # manager and an interactive shell must never disagree about where
          # the baseline marker lives, or the timer looks in the wrong root.
          state_dir=${lib.escapeShellArg "${config.xdg.stateHome}/proton-drive-sync"}
          state_key=$(printf '%s\0%s\0%s' "$direction" "$local_path" "$remote" | sha256sum | cut -c1-16)
          marker="$state_dir/initialized-$state_key"
          aborted="$state_dir/aborted-$state_key"

          resync=0
          force=0
          bisync_force=()
          for arg in "$@"; do
            case "$arg" in
              --resync) resync=1 ;;
              --force-resync)
                resync=1
                force=1
                ;;
              --force) bisync_force=(--force) ;;
              *)
                echo "proton-drive-sync: unknown argument: $arg" >&2
                exit 2
              ;;
            esac
          done

          case "$direction" in
            bisync | up | down) ;;
            *)
              echo "proton-drive-sync: unknown direction '$direction' (want bisync|up|down)" >&2
              exit 1
              ;;
          esac

          if [ "''${#bisync_force[@]}" -gt 0 ] && [ "$direction" != bisync ]; then
            echo "proton-drive-sync: --force is only valid for bisync; use --force-resync for one-way runs." >&2
            exit 2
          fi

          if [ "''${#bisync_force[@]}" -gt 0 ]; then
            if [ ! -d "$local_path" ]; then
              echo "proton-drive-sync: '$local_path' does not exist; refusing --force because recreating it could delete the remote. Mount or populate it before retrying." >&2
              exit 1
            fi
            bisync_entries=$(find -H "$local_path" -mindepth 1 -maxdepth 1 -print -quit)
            if [ -z "$bisync_entries" ]; then
              echo "proton-drive-sync: '$local_path' is empty; refusing --force because it disables the bisync deletion guard. Confirm the local source is mounted and populated before retrying." >&2
              exit 1
            fi
          fi

          if [ "$direction" = "up" ] && [ ! -d "$local_path" ]; then
            echo "proton-drive-sync: '$local_path' does not exist; refusing to create it and mirror an empty local onto '$remote'." >&2
            exit 1
          fi
          mkdir -p "$state_dir" "$local_path"

          # rclone reads RCLONE_<FLAG> for every registered flag before
          # command-line parsing (fs/config/flags.go installFlag via
          # fs.OptionToEnv), and the systemd user unit inherits the manager's
          # environment, which the eval-time extraArgs assertion cannot see.
          # Enumerating the dangerous names came up short twice: past the
          # log-routing ones that move the record run_bisync greps for,
          # RCLONE_FORCE skips both safety checks outright
          # (cmd/bisync/operations.go guards each with `if !opt.Force`),
          # RCLONE_RESYNC and RCLONE_RESYNC_MODE turn a normal fire into a
          # superset merge (the latter also inverting the conflict winner the
          # resync branch announces), RCLONE_DRY_RUN diverts the resync listings
          # to `-dry` paths while that branch still writes $marker, leaving
          # every later fire on a critical error the abort pattern never
          # matches, and RCLONE_CONFLICT_LOSER=delete drops the losing copy of
          # every conflict. Every flag this script depends on is passed
          # explicitly and the command line wins, so clear the whole namespace.
          # Prefix expansion, not compgen: nixpkgs' runtimeShell is built
          # without progcomp, where compgen exits 127 and sweeps nothing.
          for rclone_env_name in "''${!RCLONE_@}"; do
            unset "$rclone_env_name"
          done

          extra=(${lib.escapeShellArgs cfg.extraArgs})
          common=(--config ${lib.escapeShellArg "${config.xdg.configHome}/rclone/rclone.conf"} --protondrive-enable-caching=false --transfers=4 --checkers=8 --log-level INFO)
          # The cap protects unattended timer runs. --resync lifts it for a
          # confirmed one-way reconciliation unless the previous run aborted
          # fatally; --force-resync is then required to bypass the latch.
          delete_cap=(--max-delete=25)
          if [ "$resync" -eq 1 ] && { [ "$force" -eq 1 ] || [ ! -e "$aborted" ]; }; then
            delete_cap=()
          fi

          sync_one_way() {
            local rc=0
            rclone sync "$@" || rc=$?
            if [ "$rc" -eq 7 ]; then
              # rclone can delete up to --max-delete files before returning
              # this fatal error. Clear the marker so the timer cannot repeat.
              rm -f -- "$marker"
              touch "$aborted"
              echo "proton-drive-sync: rclone aborted fatally (exit $rc); cleared the baseline so the timer stops. Verify '$local_path' and '$remote' are complete, then re-run 'proton-drive-sync --resync' with the cap or '--force-resync' to bypass it." >&2
            fi
            return "$rc"
          }

          run_bisync() {
            local rc=0
            local log
            log=$(mktemp -t proton-drive-sync-bisync.XXXXXX)
            rclone bisync "$@" 2>&1 | tee -- "$log" >&2 || rc=$?
            # rclone's bisync safety checks (excess deletes, all files changed)
            # set abort without critical, so no listing is invalidated and no
            # --resync lockout follows: the next timer fire would recompute the
            # same abort from a full uncached listing of both sides, forever.
            # Latch instead. The pattern is rclone's own ERROR record for
            # exactly the two checks whose documented release is --force
            # (cmd/bisync/{deltas,operations}.go); matching the bare phrase
            # would also latch on a transferred path that happens to contain it.
            if [ "$rc" -ne 0 ] &&
              grep -qE 'ERROR +: Safety abort: (too many deletes|all files were changed)' -- "$log"; then
              touch "$aborted"
              echo "proton-drive-sync: rclone's bisync safety check aborted the run without changing either side; latched the timer off. Confirm '$local_path' is mounted and its deletions are intended, then re-run 'proton-drive-sync --force'." >&2
            fi
            rm -f -- "$log"
            return "$rc"
          }

          case "$direction" in
            up)
              # rclone sync mirrors local -> remote and deletes remote-only
              # files, so an unattended first run against a freshly created
              # empty local would wipe Proton. Gate the first run behind an
              # explicit --resync (after the operator confirms the local seed),
              # same as bisync; later timer runs proceed once the marker exists.
              if [ "$resync" -ne 1 ] && [ ! -e "$marker" ]; then
                echo "proton-drive-sync: no baseline; run 'proton-drive-sync --resync' once after confirming '$local_path' holds the desired seed (up mirrors local -> remote and deletes remote-only files)." >&2
                exit 1
              fi
              if [ "$force" -ne 1 ]; then
                local_entries=$(find -H "$local_path" -mindepth 1 -maxdepth 1 -print -quit)
                if [ -z "$local_entries" ]; then
                  echo "proton-drive-sync: '$local_path' is empty; refusing to mirror an empty local onto '$remote' (unmounted or relocated data?). Re-run with --force-resync to confirm this is intentional." >&2
                  exit 1
                fi
              fi
              sync_one_way "$local_path" "$remote" --create-empty-src-dirs "''${delete_cap[@]}" "''${common[@]}" "''${extra[@]}"
              touch "$marker"
              rm -f -- "$aborted"
              ;;
            down)
              # rclone sync mirrors remote -> local and deletes local-only
              # files, so an unattended first run would clobber a local seed.
              # Same first-run gate as up/bisync.
              if [ "$resync" -ne 1 ] && [ ! -e "$marker" ]; then
                echo "proton-drive-sync: no baseline; run 'proton-drive-sync --resync' once after confirming '$remote' holds the desired contents (down mirrors remote -> local and deletes local-only files)." >&2
                exit 1
              fi
              if [ "$force" -ne 1 ]; then
                remote_entries=$(rclone lsf --max-depth=1 "$remote" "''${common[@]}")
                if [ -z "$remote_entries" ]; then
                  echo "proton-drive-sync: '$remote' is empty; refusing to mirror an empty remote onto '$local_path'. Re-run with --force-resync to confirm this is intentional." >&2
                  exit 1
                fi
              fi
              sync_one_way "$remote" "$local_path" --create-empty-src-dirs "''${delete_cap[@]}" "''${common[@]}" "''${extra[@]}"
              touch "$marker"
              rm -f -- "$aborted"
              ;;
            bisync)
              if [ "$resync" -eq 1 ]; then
                echo "proton-drive-sync: building bisync baseline (--resync; local side wins conflicts)" >&2
                rclone bisync "$local_path" "$remote" --resync --workdir "$state_dir/bisync" --create-empty-src-dirs --resilient "''${bisync_force[@]}" "''${common[@]}" "''${extra[@]}"
                touch "$marker"
                rm -f -- "$aborted"
              elif [ ! -e "$marker" ]; then
                echo "proton-drive-sync: no bisync baseline; run 'proton-drive-sync --resync' once after confirming '$local_path' holds the desired seed contents." >&2
                exit 1
              elif [ -e "$aborted" ] && [ "''${#bisync_force[@]}" -eq 0 ]; then
                # Clearing the marker would be the wrong stop: --resync merges
                # both sides into a superset, resurrecting the very deletions
                # that tripped the check instead of propagating them.
                echo "proton-drive-sync: the previous bisync hit rclone's safety check and changed nothing; refusing to repeat it every interval. Confirm '$local_path' is mounted and its deletions are intended, then re-run with --force to propagate them (or --resync to rebuild the baseline as a superset of both sides)." >&2
                exit 1
              else
                # rclone sync treats --max-delete as an absolute file count,
                # while bisync treats the same value as a percentage.
                run_bisync "$local_path" "$remote" --workdir "$state_dir/bisync" --create-empty-src-dirs --resilient --conflict-resolve=newer --max-delete=25 "''${bisync_force[@]}" "''${common[@]}" "''${extra[@]}"
                rm -f -- "$aborted"
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
        # Four rounds of review found a flag the script passes that extraArgs
        # could still replace, each time because the two lists were maintained
        # by hand. Exposing this lets the check assert that every flag it
        # verifies on the command line is also refused here, so the pair cannot
        # drift again without a check failure.
        rejectedExtraArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          internal = true;
          readOnly = true;
          default = rejectedFlags;
          description = "Arguments refused in extraArgs, for the module's own check.";
        };

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
          default = "30m";
          example = "1h";
          description = "systemd time span between automatic syncs (OnUnitActiveSec); the 30m default limits repeated full listings against the Proton backend.";
        };

        extraArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "--bwlimit=2M" ];
          description = ''
            Extra arguments appended to every rclone sync and bisync
            invocation, not to the down-direction emptiness probe. Because they
            are appended last, they override the flags proton-drive-sync passes
            itself, so two classes are rejected at evaluation.

            Arguments that redirect or reshape rclone's log output
            (`--log-file`, `--log-format`, `--log-level`, `--log-systemd`,
            `--syslog`, `--use-json-log`): safety-abort detection reads the
            run's own stderr.

            Arguments that override a safety flag, the sync mode, or the state
            the tuple key does not cover (`--config`, `--conflict-loser`,
            `--conflict-resolve`, `--create-empty-src-dirs`, `--dry-run`,
            `--force`, `--ignore-errors`, `--max-delete`,
            `--protondrive-enable-caching`, `--resilient`, `--resync`,
            `--resync-mode`, `--workdir`): each defeats the deletion cap, the
            withholding of deletes from an errored run, the bisync safety
            checks, the conflict winner, the retry the unit relies on, the
            caching-off the Beta backend requires, the mirroring of empty
            directories, or the correspondence between the tuple marker and the
            account and listings it stands for. `--transfers`, `--checkers` and
            everything else stay tunable.

            Short options are rejected wholesale because they cluster (`-nv` is
            `--dry-run` plus `--verbose`); use the long form. The equivalent
            `RCLONE_<FLAG>` environment variables cannot be rejected at
            evaluation, so the script clears the whole `RCLONE_` namespace
            before invoking rclone.
          '';
        };
      };

      config = lib.mkMerge [
        # The CLI is the documented bootstrap/recovery path
        # (proton-drive-sync --resync), so it must exist while the timer is
        # still off; only the units are gated on cfg.enable.
        (lib.mkIf protondriveReady {
          assertions = [
            {
              assertion = rejectedArgs == [ ];
              message = "services.protonDriveSync.extraArgs is appended last on every rclone invocation, so it overrides the flags proton-drive-sync passes itself, but carries ${lib.concatStringsSep " " rejectedArgs}. Refused: ${lib.concatStringsSep " " rejectedFlags}, and every short option, because they cluster (-nv is --dry-run) and each rejected flag has a long form. The log-routing ones send rclone's ERROR record to a file, syslog or the journal, drop it below the ERROR threshold, or strip the level prefix, leaving the bisync safety abort unlatched and the timer repeating the same aborted run every ${cfg.interval}. The rest defeat the deletion cap, the safety checks, or the baseline the tuple marker records.";
            }
          ];

          home.packages = [ syncScript ];
        })

        (lib.mkIf cfg.enable {
          assertions = [
            {
              assertion = protondriveReady;
              message = "services.protonDriveSync.enable requires the protondrive rclone remote to be ready: enable programs.rclone.extended and programs.rclone.extended.protonDrive, then configure either the SOPS secret secrets/rclone_protondrive.env or the programs.rclone.extended.protonDrive.onePassword usernameRef and passwordRef op:// references (otpRef and mailboxPasswordRef are per-account optional).";
            }
          ];

          systemd.user.services.proton-drive-sync = {
            # No network-online.target dependency: the user manager has no
            # such target, so ordering against it is a no-op. OnBootSec plus
            # the periodic retry cover the offline-at-boot case.
            Unit.Description = "Proton Drive sync via rclone (${cfg.direction})";
            Service = {
              Type = "oneshot";
              TimeoutStartSec = "2h";
              ExecStart = lib.getExe syncScript;
              # local_path, remote and direction come from PROTON_DRIVE_* before
              # any other logic, and this unit inherits the user manager's
              # environment, which no eval-time guard sees: the same surface the
              # RCLONE_ sweep closes, for the values that decide what is synced
              # rather than how. A stray PROTON_DRIVE_DIRECTION=up turns every
              # scheduled bisync into a one-way mirror keyed on a tuple of its
              # own, so neither the configured tuple's baseline gate nor its
              # abort latch applies to it. Dropped for the unit only, so the
              # documented interactive override still works.
              UnsetEnvironment = "PROTON_DRIVE_LOCAL PROTON_DRIVE_REMOTE PROTON_DRIVE_DIRECTION";
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
