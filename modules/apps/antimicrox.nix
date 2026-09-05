/*
  Package: antimicrox
  Description: Graphical tool that maps gamepad buttons and axes to keyboard keys, mouse movement, and macros.
  Homepage: https://github.com/AntiMicroX/antimicrox
  Documentation: https://github.com/AntiMicroX/antimicrox/wiki
  Repository: https://github.com/AntiMicroX/antimicrox

  Summary:
    * Lets a controller drive games and desktop software that have no gamepad support of their own, with per-profile mappings, automatic profile switching per window, and a tray mode.
    * Reads controllers through SDL2 and emits the mapped events through uinput, so it works under Wayland as well as X11.

  Options:
    antimicrox: Open the mapping window.
    antimicrox --tray: Start minimized to the tray with the last profile loaded.
    antimicrox --profile FILE: Load a specific profile at start.

  Notes:
    * Installs the package's 60-antimicrox-uinput.rules so the active seat can open /dev/uinput; the rule is uaccess-only, no MODE widening. Trusted directly from the package with no local copy, so a future upstream rule change applies to every host unchecked.
    * Reads gamepads through SDL2, which does not call EVIOCGRAB. If another enabled tool (input-remapper, sc-controller) holds an exclusive grab on the same device, antimicrox still shows it as connected but receives no events, with no error surfaced anywhere.
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
