{
  flake.nixosModules.apps.gparted =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gparted ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gparted ];
    };
}
