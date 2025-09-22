{
  flake.nixosModules.apps.hdparm =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.hdparm ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.hdparm ];
    };
}
