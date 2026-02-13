/*
  Package: simplescreenrecorder
  Description: Desktop screen recorder for Linux with GUI controls and scheduling.
  Homepage: https://www.maartenbaert.be/simplescreenrecorder
  Documentation: https://www.maartenbaert.be/simplescreenrecorder
  Repository: https://github.com/MaartenBaert/ssr

  Summary:
    * Records full screen, fixed regions, or application windows with audio input support.
    * Provides interactive controls for start/stop scheduling, quality tuning, and output management.

  Options:
    --settingsfile=FILE: Load and save configuration using FILE instead of ~/.ssr/settings.conf.
    --start-recording: Start recording immediately on launch.
    --activate-schedule: Activate scheduled recording immediately.
    --no-systray: Disable system tray icon creation.
    --benchmark: Run the internal benchmark mode.
*/
_:
let
  SimplescreenrecorderModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.simplescreenrecorder.extended;
    in
    {
      options.programs.simplescreenrecorder.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable simplescreenrecorder.";
        };

        package = lib.mkPackageOption pkgs "simplescreenrecorder" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.simplescreenrecorder = SimplescreenrecorderModule;
}
