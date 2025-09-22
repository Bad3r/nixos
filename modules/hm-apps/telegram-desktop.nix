{
  flake.homeManagerModules.apps."telegram-desktop" =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.telegram-desktop ];
    };
}
