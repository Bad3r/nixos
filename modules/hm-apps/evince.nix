{
  flake.homeManagerModules.apps.evince =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.evince ];
    };
}
