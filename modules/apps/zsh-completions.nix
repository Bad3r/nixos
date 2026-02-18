/*
  Package: zsh-completions
  Description: Additional completion definitions extending stock Zsh functionality.
  Homepage: https://github.com/zsh-users/zsh-completions
  Documentation: https://github.com/zsh-users/zsh-completions#readme
  Repository: https://github.com/zsh-users/zsh-completions

  Summary:
    * Provides community-maintained completion scripts for hundreds of CLI tools beyond the default set.
    * Complements Oh My Zsh and vanilla Zsh setups with context-aware command flags and arguments.

  Options:
    -U: Use `autoload -U compinit` to load completion functions without creating aliases.
    -d: Pass to `compinit -d ~/.cache/zcompdump` to control the dumpfile location.
    -D: Use `compinit -D` to defer expensive completion initialization during startup.
*/
_:
let
  ZshCompletionsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."zsh-completions".extended;
    in
    {
      options.programs.zsh-completions.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable zsh-completions.";
        };

        package = lib.mkPackageOption pkgs "zsh-completions" { };
      };

      config = lib.mkIf cfg.enable {
        environment = {
          systemPackages = [ cfg.package ];
          etc."zsh/site-functions/_build_sh".text = ''
            #compdef build.sh

            _build_sh_hosts() {
              local flake_dir=""
              local i word host_output
              local -a hosts

              for (( i = 1; i <= CURRENT; i++ )); do
                word="''${words[i]}"
                case "''${word}" in
                  (-p|--flake-dir)
                    if (( i < CURRENT )); then
                      flake_dir="''${words[i+1]}"
                    fi
                    ;;
                  (--flake-dir=*)
                    flake_dir="''${word#--flake-dir=}"
                    ;;
                esac
              done

              if [[ -z "''${flake_dir}" ]]; then
                flake_dir="."
              fi

              host_output="$(
                nix eval --raw "''${flake_dir}#nixosConfigurations" \
                  --apply 'attrs: builtins.concatStringsSep "\n" (builtins.attrNames attrs)' \
                  2>/dev/null || true
              )"

              if [[ -n "''${host_output}" ]]; then
                while IFS= read -r host; do
                  [[ -n "''${host}" ]] && hosts+=("''${host}")
                done <<< "''${host_output}"
              fi

              if (( ''${#hosts[@]} == 0 )); then
                if command -v hostname >/dev/null 2>&1; then
                  hosts+=("$(hostname)")
                fi
              fi

              if (( ''${#hosts[@]} > 0 )); then
                _describe -t hosts "flake host" hosts
              fi
            }

            _build_sh() {
              _arguments -s -S \
                '(-p --flake-dir)'{-p,--flake-dir}'[set configuration directory]:directory:_files -/' \
                '(-t --host)'{-t,--host}'[specify target hostname]:hostname:_build_sh_hosts' \
                '(-o --offline)'{-o,--offline}'[build in offline mode]' \
                '(-v --verbose)'{-v,--verbose}'[enable verbose output]' \
                '--boot[install as next-boot generation]' \
                '--allow-dirty[allow running with a dirty git worktree]' \
                '--update[run flake metadata refresh and update before building]' \
                '--skip-hooks[skip pre-commit validation]' \
                '--skip-check[skip nix flake check validation]' \
                '--skip-all[skip all validation steps]' \
                '--skip-firmware[skip firmware refresh/check/apply after switch]' \
                '--keep-going[continue building despite failures]' \
                '--repair[repair corrupted store paths during build]' \
                '--bootstrap[use extra substituters for first build]' \
                '(-h --help)'{-h,--help}'[show help message]'
            }

            _build_sh "$@"
          '';
        };
      };
    };
in
{
  flake.nixosModules.apps.zsh-completions = ZshCompletionsModule;
}
