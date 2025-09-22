{
  flake.nixosModules.apps.f3 =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.f3 ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.f3 ];
    };
}
