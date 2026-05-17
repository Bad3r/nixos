{ inputs, ... }:
{
  flake.nixosModules.base =
    { pkgs, ... }:
    {
      imports = [ inputs.nix-index-database.nixosModules.nix-index ];

      environment.binsh = "${pkgs.dash}/bin/dash";

      programs = {
        zsh.enable = true;
        zsh.enableCompletion = true;
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
