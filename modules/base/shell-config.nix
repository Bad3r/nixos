{ inputs, ... }:
{
  flake.nixosModules.base =
    { pkgs, ... }:
    {
      imports = [ inputs.nix-index-database.nixosModules.nix-index ];

      environment.binsh = "${pkgs.dash}/bin/dash";
      environment.shellAliases.rm = "rip";
      programs = {
        zsh.enable = true;
        command-not-found.enable = true;
        nix-index = {
          enable = true;
          enableBashIntegration = false; # mutually exclusive w/ command-not-found
          enableZshIntegration = false; # mutually exclusive w/ command-not-found
        };
      };
      users.mutableUsers = true;
      users.defaultUserShell = pkgs.zsh;
    };
}
