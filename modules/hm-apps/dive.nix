{
  flake.homeManagerModules.apps.dive =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.dive ];
    };
}
