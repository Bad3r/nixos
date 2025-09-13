{ lib, ... }:
{
  flake.homeManagerModules.base =
    { pkgs, ... }:
    {
      options.pinentry = lib.mkOption {
        type = lib.types.package;
      };
      config.pinentry = pkgs.pinentry-curses;
    };

  flake.homeManagerModules.gui =
    { pkgs, ... }:
    {
      config.pinentry = lib.mkOverride 50 pkgs.pinentry-rofi; # GUI override of base
    };
}
