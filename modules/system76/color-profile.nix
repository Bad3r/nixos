_: {
  configurations.nixos.system76.module =
    { lib, ... }:
    {
      hardware.monitors.lenovo-y27q-20 = {
        enable = lib.mkDefault true;
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
