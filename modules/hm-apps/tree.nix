{
  flake.homeManagerModules.apps.tree =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.tree ];
    };
}
