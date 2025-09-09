{
  flake.nixosModules.apps.neovim =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.neovim ];
    };
}
