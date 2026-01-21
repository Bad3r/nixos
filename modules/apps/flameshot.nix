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
    * Uses services namespace since flameshot runs as a background service.
    * HM services.flameshot does not support nullable package - HM handles installation.
*/
_:
let
  FlameshotModule =
    { lib, ... }:
    {
      options.services.flameshot.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable flameshot.";
        };
      };
    };
in
{
  flake.nixosModules.apps.flameshot = FlameshotModule;
}
