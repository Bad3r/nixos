_: {
  flake.nixosModules.base =
    { lib, pkgs, ... }:
    {
      environment.binsh = "${pkgs.dash}/bin/dash";

      programs = {
        zsh = {
          enable = true;
          enableCompletion = true;
          # The owner's Home Manager zshrc runs a cached compinit after its own fpath additions.
          enableGlobalCompInit = false;
          # Accounts without a zshrc of their own (root) still get completion.
          interactiveShellInit = lib.mkBefore ''
            [[ -e ''${ZDOTDIR:-$HOME}/.zshrc ]] || { autoload -U compinit && compinit }
          '';
        };
      };
      users.mutableUsers = true;
      users.defaultUserShell = pkgs.zsh;
    };
}
