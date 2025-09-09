{
  flake.modules.nixos.apps.exiftool =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.exiftool ];
    };
}
