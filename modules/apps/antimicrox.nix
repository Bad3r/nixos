/*
  Package: antimicrox
  Description: Graphical tool that maps gamepad buttons and axes to keyboard keys, mouse movement, and macros.
  Homepage: https://github.com/AntiMicroX/antimicrox
  Documentation: https://github.com/AntiMicroX/antimicrox/wiki
  Repository: https://github.com/AntiMicroX/antimicrox

  Summary:
    * Lets a controller drive games and desktop software that have no gamepad support of their own, with per-profile mappings, automatic profile switching per window, and a tray mode.
    * Works under Wayland as well as X11.

  Options:
    antimicrox --tray: Start minimized to the tray with the last profile loaded.
    antimicrox --profile FILE: Load a specific profile at start.

  Notes:
    * Gets no events from a device another tool (input-remapper, sc-controller) grabs exclusively.
*/
_:
let
  AntimicroxModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.antimicrox.extended;
    in
    {
      options.programs.antimicrox.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable antimicrox.";
        };

        package = lib.mkPackageOption pkgs "antimicrox" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
        services.udev.packages = [ cfg.package ];
        # Same eager load as hardware.steam-hardware: the shipped rule tags the
        # node on its add event, which only fires once the module is bound.
        boot.kernelModules = [ "uinput" ];
      };
    };
in
{
  flake.nixosModules.apps.antimicrox = AntimicroxModule;
}
