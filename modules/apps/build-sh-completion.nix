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
  # Bound here rather than inline in the option default so the parse check below
  # renders the same expression the hosts install. Nothing in the text is a Nix
  # antiquotation, so this needs no module evaluation and the check stays out of
  # a NixOS configuration.
  mkBuildShCompletionPackage =
    pkgs:
    pkgs.writeTextFile {
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
          # Absolute before it reaches Lix, as build.sh resolves -p and
          # scripts/cache-coverage.sh resolves --flake-dir. A relative
          # value with no slash is a directory to the -f test below and an
          # indirect flakeref to Lix, so `-p nixos` is looked up as
          # flake:nixos in the registries: it fails into the hostname
          # fallback this retry exists to avoid, or offers the hosts of
          # whatever flake that registry entry names.
          flake_dir="''${flake_dir:A}"

          host_output="$(
            nix eval --raw "''${flake_dir}#nixosConfigurations" \
              --apply 'attrs: builtins.concatStringsSep "\n" (builtins.attrNames attrs)' \
              2>/dev/null || true
          )"

          # The bare ref cannot fetch a clean linked worktree, which is
          # where the branch workflow puts every change, so completion
          # would silently fall back to the local hostname there. Retried
          # through the primary checkout backing the worktree rather than
          # path: on the worktree itself: path: copies the tree
          # unfiltered, so a Tab press would put the ignored set build.sh
          # refuses to copy (.env, *.key, id_*, secrets/decrypted_*) into
          # the world-readable store, with no notice and no override. The
          # primary checkout shares the object store and fetches as
          # git+file, which filters ignored files. Host names differing
          # between branches only costs the hostname fallback below.
          if [[ -z "''${host_output}" && -f "''${flake_dir}/.git" ]]; then
            local main_checkout
            main_checkout="$(git -C "''${flake_dir}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
            # :h is dirname, so it turns an empty value into ".", which
            # would then resolve hosts from the completion shell's cwd
            # instead of the -p directory that was asked for.
            if [[ -n "''${main_checkout}" ]]; then
              main_checkout="''${main_checkout:h}"
            fi
            if [[ -n "''${main_checkout}" && -f "''${main_checkout}/flake.nix" ]]; then
              host_output="$(
                nix eval --raw "''${main_checkout}#nixosConfigurations" \
                  --apply 'attrs: builtins.concatStringsSep "\n" (builtins.attrNames attrs)' \
                  2>/dev/null || true
              )"
            fi
          fi

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
            '--allow-secret-copy[build even when the secrets guard flags an untracked path]' \
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
          default = mkBuildShCompletionPackage pkgs;
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
  perSystem =
    { pkgs, ... }:
    {
      # Nothing else parses this file. build-sh-completion-sync reads the flag
      # names out of the _arguments block with a grep and never reaches
      # _build_sh_hosts, so a dropped fi or esac in the host lookup shipped and
      # surfaced only where compinit autoloads it, which fails quietly: the
      # completion just stops offering hosts.
      #
      # zsh -n parses without executing, so _describe, _arguments and _files
      # being undefined here costs nothing and only real syntax errors fail.
      checks."apps/build-sh-completion-zsh-parse" =
        pkgs.runCommand "build-sh-completion-zsh-parse"
          {
            # Opts this check into the build step in .github/workflows/check.yml,
            # which is what runs it: the flake-check step only forces drvPaths,
            # and the assertion is in the build. passthru rather than a plain
            # attr, since runCommand's second argument is derivationArgs and a
            # plain one would join the derivation hash.
            passthru.runtimeCheck = true;
            nativeBuildInputs = [ pkgs.zsh ];
          }
          ''
            zsh -n ${mkBuildShCompletionPackage pkgs}/share/zsh/site-functions/_build_sh
            touch "$out"
          '';
    };

  flake.nixosModules.apps.build-sh-completion = BuildShCompletionModule;
}
