{
  flake.nixosModules.workstation = _: {
    config.programs.zsh = {
      enable = true;
      interactiveShellInit = ''
        # Disable treating # as comment in interactive shells
        # This allows using nix commands with # without escaping
        setopt NO_INTERACTIVE_COMMENTS

        # Alternative: Create convenient aliases
        alias nr='nix run nixpkgs#'
        alias ns='nix shell nixpkgs#'
        alias np='nix profile install nixpkgs#'
      '';
    };
  };
}
