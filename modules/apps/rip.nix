let
  ripModule =
    {
      config,
      lib,
      metaOwner,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.rip.extended;
      owner = metaOwner.username;

      ripWrapper = pkgs.writeShellApplication {
        name = "rip";
        runtimeInputs = [ cfg.package ];
        text = ''
          TRASH_DIR_ARGS=()
          FORCE=false
          UNBURY=false
          EMPTY_TRASH=false
          SEANCE=false
          INSPECT=false
          UNBURY_FILES=()
          FILES=()

          usage() {
            cat >&2 <<'EOF'
          rip - safe rm alternative backed by trash-cli

          Moves files and directories to the trash instead of deleting them
          permanently. Cross-device moves (e.g. USB drives) are handled correctly
          via per-device .Trash-<uid>/ directories following the FreeDesktop Trash
          specification; the home-partition trash lives at ~/.local/share/Trash.

          Usage: rip [OPTIONS] [FILES]...

          Arguments:
            [FILES]...              Files or directories to move to trash.

          Options:
            -u, --unbury [<PATH>...]
                  Restore trashed files interactively via trash-restore. Without
                  arguments, shows files deleted from the current directory. With
                  an absolute PATH, scopes the picker to that path's parent
                  directory. Relative paths always use the current directory.

            -s, --seance
                  List files deleted from the current working directory, sourced
                  from trash-list filtered by the current path prefix.

            --empty-trash
                  Permanently delete all files in the trash (trash-empty).
                  Prompts for confirmation unless --force is given. Requires a
                  TTY when prompting; non-interactive callers must pass --force.

            -i, --inspect
                  Print file info (ls -la) before trashing and prompt for
                  confirmation. Requires a TTY unless --force is given.

            --graveyard <PATH>
                  Override the trash directory for this invocation. Passed as
                  --trash-dir to trash-put, trash-list, and trash-empty.
                  Does not affect trash-restore; use the PATH arg to --unbury.

            -f, --force
                  Skip all confirmation prompts. Also silences nonexistent-file
                  errors from trash-put (equivalent to rm -f).

            -r, -R, -d
                  Accepted and ignored for rm compatibility. trash-put handles
                  directories natively so recursive and empty-dir flags are
                  redundant. Enables muscle-memory usage like: rip -rfd path/

            -h, --help
                  Print this help and exit.

          Examples:
            rip file.txt dir/              Move file.txt and dir/ to trash.
            rip -rfd path/                 rm-compatible recursive force trash.
            rip -u                         Pick a file to restore from the current dir.
            rip -u /old/path/file.txt      Scope restore picker to /old/path/.
            rip -s                         List files trashed from the current dir.
            rip --empty-trash              Empty the trash (prompts for confirmation).
            rip --empty-trash --force      Empty the trash without prompting.
            rip -i file.txt                Inspect, then confirm before trashing.
            rip --graveyard /mnt/usb/.Trash  Use a custom trash location.

          Backend: trash-cli <https://github.com/andreafrancia/trash-cli>
          EOF
          }

          # Parse a single short flag character. Called for each char in a
          # combined flag like -rfd.
          parse_short_flag() {
            case "$1" in
              h) usage; exit 0 ;;
              r|R|d) ;; # no-op: rm compat; trash-put handles dirs natively
              s) SEANCE=true ;;
              i) INSPECT=true ;;
              f) FORCE=true ;;
              u) UNBURY=true ;;
              *) echo "rip: unknown option: -$1" >&2; exit 1 ;;
            esac
          }

          while [[ $# -gt 0 ]]; do
            case "$1" in
              --help) usage; exit 0 ;;
              --empty-trash) EMPTY_TRASH=true; shift ;;
              --seance) SEANCE=true; shift ;;
              --unbury)
                UNBURY=true; shift
                while [[ $# -gt 0 ]] && [[ "$1" != -* ]]; do
                  UNBURY_FILES+=("$1"); shift
                done ;;
              --inspect) INSPECT=true; shift ;;
              --force) FORCE=true; shift ;;
              --graveyard)
                TRASH_DIR_ARGS=(--trash-dir "''${2:?--graveyard requires an argument}")
                shift 2 ;;
              --graveyard=*)
                graveyard_val="''${1#*=}"
                if [[ -z "$graveyard_val" ]]; then
                  echo "rip: --graveyard= requires a non-empty argument" >&2
                  exit 1
                fi
                TRASH_DIR_ARGS=(--trash-dir "$graveyard_val")
                shift ;;
              --) shift; FILES+=("$@"); break ;;
              --*) echo "rip: unknown option: $1" >&2; exit 1 ;;
              -*)
                # Combined short flags: parse each character in sequence.
                combined="''${1#-}"
                shift
                while [[ -n "$combined" ]]; do
                  flag="''${combined:0:1}"
                  combined="''${combined:1}"
                  parse_short_flag "$flag"
                  # -u consumes remaining positional args as restore targets.
                  if [[ "$flag" == u ]]; then
                    while [[ $# -gt 0 ]] && [[ "$1" != -* ]]; do
                      UNBURY_FILES+=("$1"); shift
                    done
                  fi
                done ;;
              *) FILES+=("$1"); shift ;;
            esac
          done

          if $EMPTY_TRASH; then
            if $FORCE; then
              trash-empty "''${TRASH_DIR_ARGS[@]}"
            else
              if [[ ! -t 0 ]]; then
                echo "rip: refusing to prompt with non-tty stdin; pass --force to confirm" >&2
                exit 1
              fi
              read -r -p "Permanently delete all trashed files? [y/N] " confirm
              if [[ "''${confirm,,}" == y ]]; then
                trash-empty "''${TRASH_DIR_ARGS[@]}"
              fi
            fi
            exit 0
          fi

          if $SEANCE; then
            # When invoked from the filesystem root, `pwd` returns `/` and
            # naive concatenation would search for `//` rather than `/`,
            # silently hiding every entry. Treat `/` as the special case
            # where the prefix is just one slash.
            seance_pwd="$(pwd)"
            if [[ "$seance_pwd" == "/" ]]; then
              seance_prefix="/"
            else
              seance_prefix="$seance_pwd/"
            fi
            trash-list "''${TRASH_DIR_ARGS[@]}" 2>/dev/null | grep -F " $seance_prefix" || true
            exit 0
          fi

          if $UNBURY; then
            if (( ''${#UNBURY_FILES[@]} == 0 )); then
              trash-restore "''${TRASH_DIR_ARGS[@]}"
              exit 0
            fi
            # `realpath -ms` mirrors `os.path.abspath` semantics used by
            # `trash-put` when it records `original_location`: normalise `.`
            # and `..` and tolerate missing components, but do not resolve
            # symlinks in parent components (so `/home -> /mnt/home` style
            # mounts still match the recorded path).
            unbury_rc=0
            for f in "''${UNBURY_FILES[@]}"; do
              rc=0
              trash-restore "''${TRASH_DIR_ARGS[@]}" -- "$(realpath -ms -- "$f")" || rc=$?
              # Preserve the first non-zero rc so the eventual exit status
              # matches the failure the operator is most likely debugging;
              # later failures are often cascades from the same root cause.
              if (( unbury_rc == 0 )); then
                unbury_rc=$rc
              fi
            done
            exit "$unbury_rc"
          fi

          if [[ ''${#FILES[@]} -eq 0 ]]; then
            usage; exit 1
          fi

          if $INSPECT; then
            ls -la -- "''${FILES[@]}"
            if ! $FORCE; then
              if [[ ! -t 0 ]]; then
                echo "rip: refusing to prompt with non-tty stdin; pass --force to confirm" >&2
                exit 1
              fi
              read -r -p "Bury these files? [y/N] " confirm
              [[ "''${confirm,,}" == y ]] || exit 0
            fi
          fi

          TRASH_PUT_ARGS=()
          $FORCE && TRASH_PUT_ARGS+=(-f)
          trash-put "''${TRASH_PUT_ARGS[@]}" "''${TRASH_DIR_ARGS[@]}" -- "''${FILES[@]}"
        '';
      };
    in
    {
      options.programs.rip.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the rip trash wrapper backed by trash-cli.";
        };

        package = lib.mkPackageOption pkgs "trash-cli" { };

        trashPath = lib.mkOption {
          type = lib.types.path;
          default = "/tmp/Trash";
          description = ''
            Directory used as the home-partition trash store. A symlink is
            created from `~/.local/share/Trash` to this path. The non-
            replacing `L` form is used, so the symlink is skipped if
            anything (real directory, file, or stale symlink with a
            different target) already exists at that path; the operator is
            responsible for migrating an existing entry. In particular,
            changing this option in a later rebuild will not retarget an
            existing symlink: remove `~/.local/share/Trash` manually, then
            rebuild, to pick up the new value.

            Defaults to `/tmp/Trash`, which is cleared on reboot. Because
            `/tmp` is a tmpfs on this configuration, every cross-device
            trash from `/home` is copied into RAM; deleting a multi-GB tree
            can therefore exhaust RAM (`ENOSPC`/OOM). Set this to a path on
            a persistent disk-backed filesystem (for example
            `/var/cache/Trash`) when storing large or long-lived deletions.

            The directory is created via `systemd.tmpfiles.rules` with the
            built-in `10d` age qualifier, so entries older than ten days are
            cleaned up automatically. Drop or override that rule directly if
            longer retention is required.
          '';
          example = "/var/cache/Trash";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [
          cfg.package
          ripWrapper
        ];

        systemd.tmpfiles.rules = [
          # Create the trash directory; clean entries older than 10 days.
          "d ${cfg.trashPath} 0700 ${owner} users 10d"
          # Bootstrap the XDG data parent so the symlink below can be placed
          # on freshly provisioned users. Without this, `L` is a no-op when
          # `~/.local/share` does not yet exist and `trash-cli` later
          # materialises `Trash` as a real directory.
          "d /home/${owner}/.local/share 0755 ${owner} users -"
          # Point home-partition trash at the configured path. Use `L` (not
          # `L+`) so any existing entry at that path is preserved; users
          # migrating from another trash implementation must move it aside
          # before this symlink takes effect.
          "L /home/${owner}/.local/share/Trash - - - - ${cfg.trashPath}"
        ];
      };
    };
in
{
  flake.nixosModules.apps.rip = ripModule;
}
