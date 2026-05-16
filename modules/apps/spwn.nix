/*
  Package: spwn
  Description: Launch commands as transient per-user systemd units.
  Homepage: nil
  Documentation: https://www.freedesktop.org/software/systemd/man/latest/systemd-run.html
  Repository: nil

  Summary:
    * Provides `spwn` for foreground transient user scopes.
    * Provides `spwnd` and `spwn -d` for detached transient user services.

  Options:
    -d, --detached: Create a transient service instead of a foreground scope.
    -v, --verbose: Print human context for the generated unit.
    -h, --help: Print usage information.
    --: Stop option parsing and treat the rest as the command.

  Notes:
    * Wraps systemd-run for the user manager only.
    * Keeps systemd-run pass-through flags out of the v1 interface.
*/
_:
let
  SpwnModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.spwn.extended;

      spwnWrapper = pkgs.writeShellApplication {
        name = "spwn";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.systemd
          pkgs.util-linux
        ];
        text = ''
          set -euo pipefail

          usage() {
            cat <<'EOF'
          spwn - launch a command as a transient per-user systemd unit

          Usage:
            spwn [OPTIONS] COMMAND [ARGS...]
            spwnd COMMAND [ARGS...]

          By default, spwn runs COMMAND in a foreground transient .scope.
          Detached mode runs COMMAND as a transient .service and prints the
          generated service unit name after systemd accepts the start request.

          Options:
            -d, --detached       Create a detached transient service.
            -v, --verbose        Print human context for the generated unit.
            -h, --help           Print this help and exit.
            --                   Stop option parsing.

          Examples:
            spwn make test
            spwn -d long-task --flag
            spwn -d -v long-task --flag
            spwnd long-task --flag
          EOF
          }

          detached=false
          verbose=false

          while [[ $# -gt 0 ]]; do
            case "$1" in
              -d|--detached)
                detached=true
                shift
                ;;
              -v|--verbose)
                verbose=true
                shift
                ;;
              -h|--help)
                usage
                exit 0
                ;;
              --)
                shift
                break
                ;;
              -*)
                echo "spwn: unknown option: $1" >&2
                exit 1
                ;;
              *)
                break
                ;;
            esac
          done

          if [[ $# -eq 0 ]]; then
            usage >&2
            exit 1
          fi

          command_name="$(basename -- "$1")"
          escaped_command="$(systemd-escape -- "$command_name")"
          uuid="$(uuidgen)"
          unit_base="spwn-''${escaped_command}-''${uuid}"

          if $detached; then
            unit="''${unit_base}.service"
            if ! run_output="$(systemd-run --user --collect --same-dir --service-type=exec --unit "$unit_base" -- "$@" 2>&1)"; then
              if [[ -n "$run_output" ]]; then
                printf '%s\n' "$run_output" >&2
              fi
              exit 1
            fi

            printf '%s\n' "$unit"
            if $verbose; then
              printf 'systemctl --user status "%s"\n' "$unit"
              printf 'journalctl --user-unit "%s"\n' "$unit"
            fi
            exit 0
          fi

          unit="''${unit_base}.scope"
          if $verbose; then
            printf 'spwn: %s\n' "$unit" >&2
          fi

          exec systemd-run --user --scope --unit "$unit_base" -- "$@"
        '';
      };

      spwndWrapper = pkgs.writeShellApplication {
        name = "spwnd";
        runtimeInputs = [ spwnWrapper ];
        text = ''
          set -euo pipefail

          exec spwn --detached "$@"
        '';
      };

      spwnCompletion = pkgs.writeTextFile {
        name = "spwn-zsh-completion";
        destination = "/share/zsh/site-functions/_spwn";
        text = ''
          #compdef spwn spwnd

          _spwn() {
            local context state line curcontext="$curcontext"
            typeset -A opt_args

            _arguments -C -s -S \
              '(- *)'{-h,--help}'[print help and exit]' \
              '(-d --detached)'{-d,--detached}'[create a detached transient service]' \
              '(-v --verbose)'{-v,--verbose}'[print generated unit context]' \
              '--[stop option parsing]' \
              '1:command:_command_names -e' \
              '*::argument:_normal'
          }

          _spwn "$@"
        '';
      };
    in
    {
      options.programs.spwn.extended.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to enable the spwn transient user unit launcher.";
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [
          spwnWrapper
          spwndWrapper
          spwnCompletion
        ];
      };
    };
in
{
  flake.nixosModules.apps.spwn = SpwnModule;
}
