{
  flake.homeManagerModules.apps.inkscape =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.inkscape ];
    };
}
