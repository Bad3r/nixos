/*
  Package: flameshot
  Description: Powerful yet simple to use screenshot software.
  Homepage: https://github.com/flameshot-org/flameshot
  Documentation: https://flameshot.org/docs/
  Repository: https://github.com/flameshot-org/flameshot

  Summary:
    * Captures screenshots with annotations, blur, arrows, and highlighting, then saves, copies, or uploads them.
    * Runs from the system tray or D-Bus with custom keyboard shortcuts.
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
