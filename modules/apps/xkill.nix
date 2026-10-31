/*
  Package: xkill
  Description: X11 utility to forcibly close hung applications by clicking their window.
  Homepage: https://www.x.org/
  Documentation: https://www.x.org/releases/current/doc/man/man1/xkill.1.xhtml
  Repository: https://gitlab.freedesktop.org/xorg/app/xkill

  Summary:
    * Changes the cursor to a crosshair so the user can terminate any client connected to the X server by clicking its window.
    * Useful for quickly closing unresponsive graphical applications without needing task managers or kill commands.

  Options:
    -display <display>: Specify the X display to operate on.
    -id <resource>: Kill a window by X resource ID without interactive selection.
*/
_:
let
  XkillModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.xkill.extended;
    in
    {
      options.programs.xkill.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable xkill.";
        };

        package = lib.mkPackageOption pkgs "xkill" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.xkill = XkillModule;
}
