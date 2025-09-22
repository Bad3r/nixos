{
  flake.nixosModules.apps.iotop =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.iotop ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.iotop ];
    };
}
