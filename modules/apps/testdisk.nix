{
  flake.nixosModules.apps.testdisk =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.testdisk ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.testdisk ];
    };
}
