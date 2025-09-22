{
  flake.homeManagerModules.apps.feh =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.feh ];
    };
}
