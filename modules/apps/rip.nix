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
        runtimeInputs = [ pkgs.trash-cli ];
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
                --graveyard <PATH>   Trash directory (default: ~/.local/share/Trash)
            -d, --decompose          Permanently delete all trashed files
            -s, --seance             List files deleted from the current directory
            -u, --unbury [<PATH>]    Restore files interactively (filtered to PATH directory)
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
              read -r -p "Permanently delete all trashed files? [y/N] " confirm
              if [[ "''${confirm,,}" == y ]]; then
                trash-empty "''${TRASH_DIR_ARGS[@]}"
              fi
            fi
            exit 0
          fi

          if $SEANCE; then
            trash-list "''${TRASH_DIR_ARGS[@]}" 2>/dev/null | grep -F "$(pwd)" || true
            exit 0
          fi

          if $UNBURY; then
            if [[ ''${#UNBURY_FILES[@]} -eq 0 ]]; then
              trash-restore
            elif [[ ''${#UNBURY_FILES[@]} -eq 1 ]] && [[ "''${UNBURY_FILES[0]}" == /* ]]; then
              trash-restore "$(dirname "''${UNBURY_FILES[0]}")"
            else
              trash-restore
            fi
            exit 0
          fi

          if [[ ''${#FILES[@]} -eq 0 ]]; then
            usage; exit 1
          fi

          if $INSPECT; then
            ls -la -- "''${FILES[@]}"
            if ! $FORCE; then
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

        trashPath = lib.mkOption {
          type = lib.types.str;
          default = "/tmp/Trash";
          description = ''
            Directory used as the home-partition trash store.
            A symlink is created from ~/.local/share/Trash to this path.
            Defaults to /tmp/Trash which is cleared on reboot.
            For persistent trash use a path outside /tmp.
          '';
          example = "/var/cache/Trash";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [
          pkgs.trash-cli
          ripWrapper
        ];

        systemd.tmpfiles.rules = [
          # Create the trash directory; clean entries older than 10 days.
          "d ${cfg.trashPath} 0700 ${owner} users 10d"
          # Point home-partition trash at the configured path.
          "L+ /home/${owner}/.local/share/Trash - - - - ${cfg.trashPath}"
        ];
      };
    };
in
{
  flake.nixosModules.apps.rip = ripModule;
}
