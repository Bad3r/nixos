/*
  Package: build-sh-completion
  Description: Zsh completion for this flake's ./build.sh helper.

  Summary:
    * Ships a `_build_sh` completion function under share/zsh/site-functions
      so NixOS's zsh module finds it via `$NIX_PROFILES/share/zsh/site-functions`
      (the fpath populated by nixpkgs' programs.zsh module).
    * Completes the flags documented in build.sh and resolves --host candidates
      from `nixosConfigurations` when a flake directory is reachable.
*/
_:
let
  BuildShCompletionModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.build-sh-completion.extended;
    in
    {
      options.programs.build-sh-completion.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the _build_sh zsh completion.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.writeTextFile {
            name = "build-sh-zsh-completion";
            destination = "/share/zsh/site-functions/_build_sh";
            text = ''
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
                  '--fallback[build from source if binary substitutes fail]' \
                  '--bootstrap[use extra substituters for first build]' \
                  '--cache-coverage[fail before deploy on unexpected local source builds]' \
                  '(-h --help)'{-h,--help}'[show help message]'
              }

              _build_sh "$@"
            '';
          };
          defaultText = lib.literalExpression "pkgs.writeTextFile { ... installs _build_sh ... }";
          description = "Derivation providing the zsh completion file for build.sh.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.build-sh-completion = BuildShCompletionModule;
}
