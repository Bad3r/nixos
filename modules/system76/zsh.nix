{
  configurations.nixos.system76.module = {
    programs.zsh = {
      enable = true;
      interactiveShellInit = ''
        # Source Home Manager session variables from per-user profile path.
        source "/etc/profiles/per-user/vx/etc/profile.d/hm-session-vars.sh"

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

        # Register custom build.sh completions from zsh site-functions.
        if (( $+functions[compdef] )); then
          autoload -Uz _build_sh
          compdef _build_sh build.sh
          compdef _build_sh ./build.sh
          compdef _build_sh "$HOME/nixos/build.sh"
        fi

        setopt NO_INTERACTIVE_COMMENTS
        alias nr='nix run nixpkgs#'
        alias ns='nix shell nixpkgs#'
        alias np='nix profile install nixpkgs#'
      '';
    };
  };
}
