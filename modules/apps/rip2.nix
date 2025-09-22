{
  flake.nixosModules.apps.rip2 =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.rip2 ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.rip2 ];
    };
}
