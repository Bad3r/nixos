{ inputs, ... }:
{
  flake.nixosModules.base =
    { pkgs, ... }:
    {
      imports = [ inputs.nix-index-database.nixosModules.nix-index ];

      environment.binsh = "${pkgs.dash}/bin/dash";
      environment.shellAliases.rm = "rip";
      programs.zsh.enable = true;
      programs.command-not-found.enable = false;
      users.mutableUsers = true;
      users.defaultUserShell = pkgs.zsh;
    };
}
