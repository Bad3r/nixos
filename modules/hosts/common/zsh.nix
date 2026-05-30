{
  lib,
  metaOwner,
  ...
}:
let
  inherit (metaOwner) username;
  body =
    { config, ... }:
    let
      atuinCfg = config.programs.atuin.extended;
      lazygitCfg = config.programs.lazygit.extended;
      starshipCfg = config.programs.starship.extended;
      zoxideCfg = config.programs.zoxide.extended;
    in
    {
      programs.zsh = {
        enable = true;
        interactiveShellInit = ''
          # Source Home Manager session variables from per-user profile path.
          source "/etc/profiles/per-user/${username}/etc/profile.d/hm-session-vars.sh"

          # Keep bulk Nix CLI config in build.sh / flake nixConfig.
          # Here we only inject GitHub auth so Nix fetches are authenticated.
          if command -v gh &>/dev/null; then
            _nix_github_token="$(gh auth token 2>/dev/null || true)"
            if [[ -n $_nix_github_token ]]; then
              _nix_access_tokens_line="access-tokens = github.com=$_nix_github_token"

              _nix_config_current=""
              if (( $+NIX_CONFIG )); then
                _nix_config_current="$NIX_CONFIG"
              fi

              case "$_nix_config_current" in
                (*"$_nix_access_tokens_line") ;;
                (*)
                  if [[ -n $_nix_config_current ]]; then
                    _nix_config_current+=$'\n'
                  fi
                  _nix_config_current+="$_nix_access_tokens_line"
                  NIX_CONFIG="$_nix_config_current"
                  ;;
              esac

              export NIX_CONFIG
              unset _nix_access_tokens_line
              unset _nix_config_current
            fi
            unset _nix_github_token
          fi

          # Mirror bash behavior: expose hostname through HOSTNAME in zsh.
          export HOSTNAME="$HOST"

          # Source kitty's shell integration when running inside kitty.
          # Why: HM's programs.kitty sets shell_integration=no-rc, but it only
          # auto-sources from HM-managed zsh; this zsh is NixOS-managed.
          if [[ -n "$KITTY_INSTALLATION_DIR" && -f "$KITTY_INSTALLATION_DIR"/shell-integration/zsh/kitty-integration ]]; then
            export KITTY_SHELL_INTEGRATION="''${KITTY_SHELL_INTEGRATION:-enabled}"
            autoload -Uz -- "$KITTY_INSTALLATION_DIR"/shell-integration/zsh/kitty-integration
            kitty-integration
            unfunction kitty-integration
          fi

          # Initialize integrations in NixOS-managed zsh. HM zsh is disabled.
          ${lib.optionalString atuinCfg.enable ''
            if [[ $options[zle] = on ]]; then
              eval "$(${lib.getExe atuinCfg.package} init zsh --disable-up-arrow)"
            fi
          ''}

          ${lib.optionalString lazygitCfg.enable ''
            function lg() {
              local -x LAZYGIT_NEW_DIR_FILE="''${XDG_CACHE_HOME:-$HOME/.cache}/lazygit/newdir"
              local lazygit_status

              mkdir -p -- "$(dirname -- "$LAZYGIT_NEW_DIR_FILE")"
              ${lib.getExe lazygitCfg.package} "$@"
              lazygit_status=$?

              if [[ -f "$LAZYGIT_NEW_DIR_FILE" ]]; then
                local lazygit_new_dir
                lazygit_new_dir="$(cat -- "$LAZYGIT_NEW_DIR_FILE")"
                rm -f -- "$LAZYGIT_NEW_DIR_FILE" >/dev/null

                if [[ -n "$lazygit_new_dir" && -d "$lazygit_new_dir" ]]; then
                  cd -- "$lazygit_new_dir"
                fi
              fi

              return "$lazygit_status"
            }
          ''}

          ${lib.optionalString zoxideCfg.enable ''
            eval "$(${lib.getExe zoxideCfg.package} init zsh)"
          ''}

          ${lib.optionalString starshipCfg.enable ''
            if [[ $TERM != "dumb" ]]; then
              eval "$(${lib.getExe starshipCfg.package} init zsh)"
            fi
          ''}

          # Register custom build.sh completions from zsh site-functions.
          if (( $+functions[compdef] )); then
            autoload -Uz _build_sh
            compdef _build_sh build.sh
            compdef _build_sh ./build.sh
            compdef _build_sh "$HOME/nixos/build.sh"
          fi

          setopt NO_INTERACTIVE_COMMENTS
          git-sync-fork() {
            local branch

            branch="$(git branch --show-current)" || return
            if [[ -z "$branch" ]]; then
              printf 'git-sync-fork: not on a branch\n' >&2
              return 1
            fi

            git pull --no-edit upstream "$branch" && git push origin "$branch"
          }
          alias nr='nix run nixpkgs#'
          alias ns='nix shell nixpkgs#'
          alias np='nix profile install nixpkgs#'
        '';
      };
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
