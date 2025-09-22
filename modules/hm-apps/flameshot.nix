{
  flake.homeManagerModules.apps.flameshot =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.flameshot ];
    };
}
