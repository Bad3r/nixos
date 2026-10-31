/*
  Package: dualsensectl
  Description: Command-line tool for the Sony DualSense and DualSense Edge controllers: lightbar, LEDs, microphone, speaker, adaptive triggers, battery, and power-off.
  Homepage: https://github.com/nowrep/dualsensectl
  Documentation: https://github.com/nowrep/dualsensectl/blob/main/README.md
  Repository: https://github.com/nowrep/dualsensectl

  Summary:
    * Works the same over USB and Bluetooth.

  Options:
    dualsensectl -l: List connected controllers.
    dualsensectl battery: Print the charge level and charging state.
    dualsensectl lightbar RED GREEN BLUE [BRIGHTNESS]: Set the lightbar color.
    dualsensectl player-leds NUMBER: Set the player indicator LEDs (0 disables them).
    dualsensectl trigger TRIGGER MODE ...: Apply an adaptive-trigger effect to left, right, or both.
    dualsensectl power-off: Turn a Bluetooth-connected controller off.
*/
_:
let
  DualsensectlModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.dualsensectl.extended;
      # The hid parent is named <bus>:054C:<pid>.<n> on USB (0003) and Bluetooth
      # (0005) alike, so one KERNELS glob per model covers both transports.
      # uaccess only, no MODE/GROUP: the raw HID stream carries every input.
      udevRules = pkgs.writeTextFile {
        name = "dualsensectl-udev-rules";
        destination = "/etc/udev/rules.d/70-dualsensectl.rules";
        text = ''
          # DualSense
          KERNEL=="hidraw*", SUBSYSTEM=="hidraw", KERNELS=="*054C:0CE6*", TAG+="uaccess"
          # DualSense Edge
          KERNEL=="hidraw*", SUBSYSTEM=="hidraw", KERNELS=="*054C:0DF2*", TAG+="uaccess"
        '';
      };
    in
    {
      options.programs.dualsensectl.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable dualsensectl.";
        };

        package = lib.mkPackageOption pkgs "dualsensectl" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
        services.udev.packages = [ udevRules ];
      };
    };
in
{
  flake.nixosModules.apps.dualsensectl = DualsensectlModule;
}
