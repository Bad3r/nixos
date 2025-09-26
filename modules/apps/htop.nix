{
  flake.nixosModules.apps.htop =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.htop ];
    };
}
