{
  flake.nixosModules.apps.exiftool =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.exiftool ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.exiftool ];
    };
}
