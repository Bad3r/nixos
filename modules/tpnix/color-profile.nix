{ config, lib, ... }:
let
  hasLenovoMonitorModule = lib.hasAttrByPath [
    "flake"
    "nixosModules"
    "hardware-lenovo-y27q-20"
  ] config;
in
{
  configurations.nixos.tpnix.module = lib.mkIf hasLenovoMonitorModule {
    hardware.monitors.lenovo-y27q-20 = {
      enable = lib.mkDefault false;
      fallbackDeviceIds = lib.mkAfter [
        "xrandr-HDMI-0"
        "xrandr-HDMI_0"
        "xrandr-HDMI-1"
        "xrandr-HDMI_1"
        "xrandr-DP-0"
        "xrandr-DP_0"
        "xrandr-DP-1"
        "xrandr-DP_1"
        "xrandr-DP-2"
        "xrandr-DP_2"
        "xrandr-USB-C-0"
        "xrandr-USB_C_0"
        "xrandr-USB-C-1"
        "xrandr-USB_C_1"
      ];
    };
  };
}
