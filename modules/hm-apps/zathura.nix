{
  flake.homeManagerModules.apps.zathura =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.zathura ];
    };
}
