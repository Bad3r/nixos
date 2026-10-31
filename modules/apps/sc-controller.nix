/*
  Package: sc-controller
  Description: User-mode gamepad driver, mapper, and GTK GUI with Steam-Input-style profiles, gyro aiming, and on-screen menus.
  Homepage: https://github.com/C0rn3j/sc-controller
  Documentation: https://github.com/C0rn3j/sc-controller/blob/master/README.md
  Repository: https://github.com/C0rn3j/sc-controller

  Summary:
    * Drives Steam Controllers, DualShock 4, DualSense, and any evdev gamepad, translating them into keyboard, mouse, or virtual-gamepad events through uinput.
    * Profiles cover mode shifts, action layers, gyro aiming, macros, radial menus, and an on-screen keyboard; `scc-daemon` keeps the mapping active without the GUI.

  Options:
    scc-daemon start: Run the mapping daemon on its own.

  Notes:
    * Upstream's world-writable udev rules are replaced by a uaccess-only uinput rule.
    * DualSense over hidraw (`ds5drv`) needs `programs.dualsensectl.extended` or `hardware.steam-hardware`.
    * Steam Controller dongle and DualShock 4 hidraw need `hardware.steam-hardware`.
    * Conflicts with input-remapper on the same gamepad.
*/
_:
let
  ScControllerModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.sc-controller.extended;
      # Same shape as antimicrox's shipped rule; the package's own 69-sc-controller.rules
      # would set MODE 0666 on /dev/uinput and every 054c USB device.
      udevRules = pkgs.writeTextFile {
        name = "sc-controller-udev-rules";
        destination = "/etc/udev/rules.d/60-sc-controller-uinput.rules";
        text = ''
          SUBSYSTEM=="misc", KERNEL=="uinput", OPTIONS+="static_node=uinput", TAG+="uaccess"
        '';
      };
    in
    {
      options.programs.sc-controller.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable sc-controller.";
        };

        package = lib.mkPackageOption pkgs "sc-controller" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
        services.udev.packages = [ udevRules ];
        # Same eager load as hardware.steam-hardware: the rule tags the node on
        # its add event, which only fires once the module is bound.
        boot.kernelModules = [ "uinput" ];
      };
    };
in
{
  flake.nixosModules.apps.sc-controller = ScControllerModule;
}
