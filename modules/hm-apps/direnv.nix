/*
  Package: direnv
  Description: Shell extension that loads/unloads environment variables based on the current directory.
  Homepage: https://direnv.net
  Documentation: https://direnv.net/#usage
  Repository: https://github.com/direnv/direnv

  Summary:
    * Hooks into your shell to watch `.envrc` files and adjust environment variables automatically.
    * Integrates with `nix-direnv` for fast, cache-aware Nix environment activation.
    * Essential for Nix development workflows - dramatically speeds up `nix develop` environments.

  Features:
    * nix-direnv integration for cached Nix shells
    * Automatic shell integration (Zsh, Bash)
    * Silent loading to reduce noise
    * Custom stdlib additions for enhanced functionality

  Usage:
    * `echo 'use flake' > .envrc && direnv allow` — Activate Nix flake in current directory
    * `direnv allow` — Authorize the current `.envrc` file
    * `direnv reload` — Re-evaluate environment after editing `.envrc`
*/

_: {
  flake.homeManagerModules.apps.direnv =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "direnv" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.direnv = {
          enable = true;

          # nix-direnv: Faster, cached Nix shell loading
          nix-direnv.enable = true;

          # Shell integrations
          enableZshIntegration = true;
          enableBashIntegration = true;

          # Configuration
          config = {
            global = {
              # Reduce noise
              warn_timeout = "30s";

              # Disable hints for common commands
              hide_env_diff = false;
            };

            whitelist = {
              # Allow direnv in home directory projects
              prefix = [
                "~/git"
                "~/projects"
                "~/src"
              ];
            };
          };

          # Custom stdlib additions
          stdlib = ''
            # Enhanced 'layout' function for common project types
            layout_poetry() {
              if [[ ! -f pyproject.toml ]]; then
                log_error 'No pyproject.toml found. Use `poetry new` or `poetry init` to create one first.'
                exit 2
              fi

              local VENV=$(poetry env info --path 2>/dev/null ; true)

              if [[ -z $VENV || ! -d $VENV/bin ]]; then
                log_status "No virtual environment exists. Executing \`poetry install\` to create one."
                poetry install
                VENV=$(poetry env info --path)
              fi

              export VIRTUAL_ENV=$VENV
              export POETRY_ACTIVE=1
              PATH_add "$VENV/bin"
            }

            # Use this in .envrc: use flake . --impure
            use_flake_impure() {
              watch_file flake.nix
              watch_file flake.lock
              eval "$(nix print-dev-env --impure --profile "$(direnv_layout_dir)/flake-profile")"
            }
          '';
        };

        # Environment variables
        home.sessionVariables = {
          # Direnv layout directory (cached builds)
          DIRENV_LOG_FORMAT = lib.mkDefault ""; # Silent by default, set to show logs if needed
        };
      };
    };
}
