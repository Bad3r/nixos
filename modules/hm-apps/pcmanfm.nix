{
  flake.homeManagerModules.apps.pcmanfm =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.pcmanfm ];
    };
}
