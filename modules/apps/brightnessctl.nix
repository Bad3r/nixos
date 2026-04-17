/*
  Package: brightnessctl
  Description: Program to read and control device brightness on Linux.
  Homepage: https://github.com/Hummer12007/brightnessctl
  Documentation: https://github.com/Hummer12007/brightnessctl#usage
  Repository: https://github.com/Hummer12007/brightnessctl

  Summary:
    * Controls backlight and LED brightness from the command line, defaulting to the first compatible device when no target is specified.
    * Supports absolute values, percentages, relative deltas, and save/restore workflows for brightness automation.

  Options:
    -l: List devices with available brightness controls.
    --device: Target a specific device name; wildcards are supported.
    --class: Restrict device selection to a brightness class such as backlight or leds.
    set: Set brightness using absolute values, percentages, or relative deltas.
    --save: Save the current brightness state before applying a change.
    --restore: Restore the previously saved brightness state.
*/
_:
let
  BrightnessctlModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.brightnessctl.extended;
    in
    {
      options.programs.brightnessctl.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable brightnessctl.";
        };

        package = lib.mkPackageOption pkgs "brightnessctl" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.brightnessctl = BrightnessctlModule;
}
