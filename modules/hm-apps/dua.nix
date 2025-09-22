{
  flake.homeManagerModules.apps.dua =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.dua ];
    };
}
