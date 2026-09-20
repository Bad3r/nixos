{ inputs, ... }:
{
  flake.nixosModules.base =
    { lib, pkgs, ... }:
    {
      imports = [ inputs.nix-index-database.nixosModules.nix-index ];

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
        # nix-index-database module disables command-not-found and provides
        # nix-index with pre-built database; shell integration replaces command-not-found
        nix-index = {
          enable = true;
          enableBashIntegration = true;
          enableZshIntegration = true;
        };
      };
      users.mutableUsers = true;
      users.defaultUserShell = pkgs.zsh;
    };
}
