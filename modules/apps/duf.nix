{
  flake.nixosModules.apps.duf =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.duf ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.duf ];
    };
}
