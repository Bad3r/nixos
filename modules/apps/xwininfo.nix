/*
  Package: xwininfo
  Description: Utility to print information about windows on an X server.
  Homepage: https://gitlab.freedesktop.org/xorg/app/xwininfo
  Documentation: https://www.x.org/archive/X11R7.5/doc/man/man1/xwininfo.1.html
  Repository: https://gitlab.freedesktop.org/xorg/app/xwininfo

  Summary:
    * Displays information about a selected X window or the root window.
    * Reports window geometry, hierarchy, properties, events, and window-manager details.

  Options:
    -root: Select the root window.
    -id: Select a window by its X window ID.
    -name: Select a window by name.
    -tree: Display the selected window's hierarchy.
    -all: Display all available window information.

  Notes:
    * Requires an X11 display.
*/
_:
let
  XwininfoModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.xwininfo.extended;
    in
    {
      options.programs.xwininfo.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable xwininfo.";
        };

        package = lib.mkPackageOption pkgs "xwininfo" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.xwininfo = XwininfoModule;
}
