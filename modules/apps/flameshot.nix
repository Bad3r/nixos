/*
  Package: flameshot
  Description: Powerful yet simple to use screenshot software.
  Homepage: https://github.com/flameshot-org/flameshot
  Documentation: https://flameshot.org/docs/
  Repository: https://github.com/flameshot-org/flameshot

  Summary:
    * Captures screenshots with configurable annotations, blur, arrows, highlighting, and upload/share integrations.
    * Supports system tray controls, DBus shortcuts, Wayland/X11 backends, and custom keyboard shortcuts.

  Notes:
    * This module provides the enable flag for the Home Manager flameshot service.
    * Package installation is handled by the Home Manager module, not this NixOS module.
    * Uses services namespace since flameshot runs as a background service.
*/
_:
let
  FlameshotModule =
    { lib, pkgs, ... }:
    {
      options.services.flameshot.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable flameshot.";
        };

        package = lib.mkPackageOption pkgs "flameshot" { };
      };
    };
in
{
  flake.nixosModules.apps.flameshot = FlameshotModule;
}
