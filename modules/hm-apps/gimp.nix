{
  flake.homeManagerModules.apps.gimp =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.gimp ];
    };
}
