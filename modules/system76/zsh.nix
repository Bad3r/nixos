{
  configurations.nixos.system76.module = {
    programs.zsh = {
      enable = true;
      interactiveShellInit = ''
        # Source Home Manager session variables (for home.sessionVariables, home.sessionPath)
        source "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"

        setopt NO_INTERACTIVE_COMMENTS
        alias nr='nix run nixpkgs#'
        alias ns='nix shell nixpkgs#'
        alias np='nix profile install nixpkgs#'
      '';
    };
  };
}
