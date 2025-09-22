{
  flake.nixosModules.apps.gopass =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gopass ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gopass ];
    };
}
