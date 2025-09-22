{
  flake.homeManagerModules.apps.sqlite =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.sqlite ];
    };
}
