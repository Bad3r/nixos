{ config, lib, ... }:
let
  lenovoMonitorExists = lib.hasAttrByPath [
    "flake"
    "nixosModules"
    "hardware-lenovo-y27q-20"
  ] config;
  hostsRegistry = config.flake.lib.nixos.hosts or { };

  body =
    { hostName, lib, ... }:
    {
      # hardware.monitors.* is declared by the optional hardware-lenovo-y27q-20
      # module; optionalAttrs keeps the path untouched when the module is
      # absent (mkIf false would still abort on the undeclared option).
      config = lib.optionalAttrs lenovoMonitorExists {
        hardware.monitors.lenovo-y27q-20 = {
          enable = lib.mkDefault ((hostsRegistry.${hostName} or { }).lenovoMonitorAttached or false);
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
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
