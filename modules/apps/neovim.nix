{
  flake.nixosModules.apps.neovim =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.neovim ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.neovim ];
    };
}
