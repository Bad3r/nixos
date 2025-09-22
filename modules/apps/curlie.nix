{
  flake.nixosModules.apps.curlie =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.curlie ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.curlie ];
    };
}
