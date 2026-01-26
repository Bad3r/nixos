{
  configurations.nixos.system76.module = {
    programs.zsh = {
      enable = true;
      interactiveShellInit = ''
        # Source Home Manager session variables (for home.sessionVariables, home.sessionPath)
        source "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"

        # Nix CLI config: enable flakes, pipe-operators, and GitHub authentication
        # Keep aligned with build.sh and flake.nix nixConfig
        NIX_CONFIG="experimental-features = nix-command flakes pipe-operators
accept-flake-config = true
allow-import-from-derivation = false
abort-on-warn = true"
        if command -v gh &>/dev/null && gh auth status &>/dev/null; then
          NIX_CONFIG+="
access-tokens = github.com=$(gh auth token)"
        fi
        export NIX_CONFIG

        setopt NO_INTERACTIVE_COMMENTS
        alias nr='nix run nixpkgs#'
        alias ns='nix shell nixpkgs#'
        alias np='nix profile install nixpkgs#'
      '';
    };
  };
}
