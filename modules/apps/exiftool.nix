{
  flake.nixosModules.apps.exiftool =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.exiftool ];
    };
}
