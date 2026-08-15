/*
  Package: xdotool
  Description: Fake keyboard/mouse input, window management, and more.
  Homepage: https://www.semicomplete.com/projects/xdotool/
  Documentation: https://github.com/jordansissel/xdotool/blob/main/xdotool.pod
  Repository: https://github.com/jordansissel/xdotool

  Summary:
    * Simulates keyboard input and mouse activity through the XTEST extension and Xlib.
    * Searches, activates, moves, resizes, and manipulates X11 windows.

  Options:
    key: Send one or more keystrokes to a window.
    type: Type a string into the active or selected window.
    search: Find windows by name, class, role, or other properties.
    getmouselocation: Print the pointer coordinates, screen, and window ID.

  Notes:
    * Requires an X11 display; many operations do not work correctly under Wayland.
*/
_:
let
  XdotoolModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.xdotool.extended;
    in
    {
      options.programs.xdotool.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable xdotool.";
        };

        package = lib.mkPackageOption pkgs "xdotool" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.xdotool = XdotoolModule;
}
