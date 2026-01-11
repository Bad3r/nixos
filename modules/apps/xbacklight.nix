/*
  Package: xbacklight
  Description: Utility for adjusting screen backlight brightness via the X RandR extension.
  Homepage: https://www.x.org/
  Documentation: https://www.x.org/releases/X11R7.7/doc/man/man1/xbacklight.1.xhtml
  Repository: https://gitlab.freedesktop.org/xorg/app/xbacklight

  Summary:
    * Modifies backlight brightness on systems where the X server exposes RANDR backlight properties (primarily X11 laptops).
    * Useful for scripting brightness adjustments in window managers lacking built-in controls.

  Options:
    xbacklight -set <percentage>: Set brightness to an absolute percentage.
    xbacklight -inc <value>: Increase brightness by a relative percentage.
    xbacklight -dec <value>: Decrease brightness by a relative percentage.
    -time <ms>: Set transition time for fades.

  Example Usage:
    * `xbacklight -set 50` — Set brightness to 50%.
    * `xbacklight -inc 10` — Increase brightness by 10%.
    * `xbacklight -dec 20 -time 200` — Fade brightness down by 20% over 200 ms.
*/
_:
let
  XbacklightModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.xbacklight.extended;
    in
    {
      options.programs.xbacklight.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable xbacklight brightness control.";
        };

        package = lib.mkPackageOption pkgs [ "xorg" "xbacklight" ] { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.xbacklight = XbacklightModule;
}
