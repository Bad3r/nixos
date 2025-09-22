{
  flake.homeManagerModules.apps.ncdu =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.ncdu ];
    };
}
