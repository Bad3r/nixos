/*
  Package: firmware-manager
  Description: GTK front end for firmware updates from fwupd and system76-firmware.
  Homepage: https://github.com/pop-os/firmware-manager
  Documentation: https://github.com/pop-os/firmware-manager#readme
  Repository: https://github.com/pop-os/firmware-manager

  Summary:
    * Lists devices with available firmware updates and schedules or applies them.
    * Reaches LVFS devices through the fwupd daemon, which `services.fwupd.enable` runs.

  Options:
    com.system76.FirmwareManager: Open the firmware manager window.
    -v: Raise the log level; repeat it for more detail.

  Example Usage:
    * `com.system76.FirmwareManager -vv` -- Open the window with verbose logging.
*/
_:
let
  FirmwareManagerModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."firmware-manager".extended;
    in
    {
      options.programs.firmware-manager.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable firmware-manager.";
        };

        package = lib.mkPackageOption pkgs "firmware-manager" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."firmware-manager" = FirmwareManagerModule;
}
