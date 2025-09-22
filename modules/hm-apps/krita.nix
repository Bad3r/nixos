{
  flake.homeManagerModules.apps.krita =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.krita ];
    };
}
