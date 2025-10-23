{
  configurations.nixos.system76.module = {
    programs.zsh = {
      enable = true;
      interactiveShellInit = ''
        setopt NO_INTERACTIVE_COMMENTS
        alias nr='nix run nixpkgs#'
        alias ns='nix shell nixpkgs#'
        alias np='nix profile install nixpkgs#'
      '';
    };
  };
}
