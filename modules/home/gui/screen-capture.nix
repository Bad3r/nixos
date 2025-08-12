
# modules/screen-capture.nix

{
  flake.modules.homeManager.gui =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.kooha ];
    };
}
