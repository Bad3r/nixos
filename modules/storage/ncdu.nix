{
  flake.homeManagerModules.base =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.ncdu ];
    };
}
