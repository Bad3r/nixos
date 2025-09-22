{
  flake.nixosModules.apps.parted =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.parted ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.parted ];
    };
}
