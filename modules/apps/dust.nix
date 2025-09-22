{
  flake.nixosModules.apps.dust =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.dust ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.dust ];
    };
}
