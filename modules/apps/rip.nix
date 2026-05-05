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
          DECOMPOSE=false
          SEANCE=false
          INSPECT=false
          UNBURY_FILES=()
          FILES=()

          usage() {
            cat >&2 <<'EOF'
          rip: safe rm alternative (trash-cli backend)

          Usage: rip [OPTIONS] [FILES]...

          Options:
                --graveyard <PATH>   Override the default trash directory
            -d, --decompose          Permanently delete all trashed files
            -s, --seance             List files deleted from the current directory
            -u, --unbury [<FILES>]   Restore listed files (interactive picker if none given)
            -i, --inspect            Show file info before trashing
            -f, --force              Skip confirmation prompts
            -h, --help               Show this help
          EOF
          }

          while [[ $# -gt 0 ]]; do
            case "$1" in
              -h|--help) usage; exit 0 ;;
              -d|--decompose) DECOMPOSE=true; shift ;;
              -s|--seance) SEANCE=true; shift ;;
              -u|--unbury)
                UNBURY=true; shift
                while [[ $# -gt 0 ]] && [[ "$1" != -* ]]; do
                  UNBURY_FILES+=("$1"); shift
                done ;;
              -i|--inspect) INSPECT=true; shift ;;
              -f|--force) FORCE=true; shift ;;
              --graveyard)
                TRASH_DIR_ARGS=(--trash-dir "''${2:?--graveyard requires an argument}")
                shift 2 ;;
              --graveyard=*)
                TRASH_DIR_ARGS=(--trash-dir "''${1#*=}"); shift ;;
              --) shift; FILES+=("$@"); break ;;
              -*) echo "rip: unknown option: $1" >&2; exit 1 ;;
              *) FILES+=("$1"); shift ;;
            esac
          done

          if $DECOMPOSE; then
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
            seance_prefix="$(pwd)/"
            trash-list "''${TRASH_DIR_ARGS[@]}" 2>/dev/null | grep -F " $seance_prefix" || true
            exit 0
          fi

          if $UNBURY; then
            if (( ''${#UNBURY_FILES[@]} == 0 )); then
              trash-restore "''${TRASH_DIR_ARGS[@]}"
            else
              for f in "''${UNBURY_FILES[@]}"; do
                trash-restore "''${TRASH_DIR_ARGS[@]}" -- "$(realpath -m -- "$f")"
              done
            fi
            exit 0
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

          trash-put "''${TRASH_DIR_ARGS[@]}" -- "''${FILES[@]}"
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
            created from `~/.local/share/Trash` to this path; if that path
            already exists as a real directory it is preserved (the symlink
            is skipped) and must be migrated manually.

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
