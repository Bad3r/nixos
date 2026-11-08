/*
  Package: xdpyinfo
  Description: Utility for inspecting an X display and its capabilities.
  Homepage: https://gitlab.freedesktop.org/xorg/app/xdpyinfo
  Documentation: https://www.x.org/releases/current/doc/man/man1/xdpyinfo.1.xhtml
  Repository: https://gitlab.freedesktop.org/xorg/app/xdpyinfo

  Summary:
    * Reports display dimensions, supported depths, visuals, and extensions.
    * Helps diagnose differences between Xvfb and other X servers.
*/
_:
let
  XdpyinfoModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.xdpyinfo.extended;
    in
    {
      options.programs.xdpyinfo.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable xdpyinfo.";
        };

        package = lib.mkPackageOption pkgs "xdpyinfo" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.xdpyinfo = XdpyinfoModule;
}
