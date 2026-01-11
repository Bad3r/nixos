/*
  Package: spectacle
  Description: KDE screenshot utility supporting full screen, window, region capture, and editing annotations.
  Homepage: https://apps.kde.org/spectacle/
  Documentation: https://docs.kde.org/stable5/en/spectacle/spectacle/
  Repository: https://invent.kde.org/graphics/spectacle

  Summary:
    * Captures screenshots with configurable shortcuts, timers, annotation tools, and integration with clipboard or file-saving workflows.
    * Supports recording screen as video (Wayland) in recent versions and shares via KDE Connect or online services.

  Options:
    spectacle: Launch the GUI interface.
    spectacle --fullscreen: Capture the entire screen immediately.
    spectacle --region: Start region selection mode.
    spectacle --delay <seconds>: Delay capture by a specified amount.
    spectacle --clipboard: Copy the capture directly to the clipboard.

  Example Usage:
    * `spectacle --region --clipboard` — Select an area and copy it to the clipboard for pasting.
    * `spectacle --fullscreen --delay 5 -o ~/Pictures/screenshot.png` — Capture the full screen after a 5-second delay and save it.
    * Use the built-in annotation tools to highlight portions of a capture before saving.
*/
_:
let
  SpectacleModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.spectacle.extended;
    in
    {
      options.programs.spectacle.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Spectacle screenshot utility.";
        };

        package = lib.mkPackageOption pkgs [ "kdePackages" "spectacle" ] { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.spectacle = SpectacleModule;
}
