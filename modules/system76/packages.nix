{ lib, ... }:
{
  nixpkgs.allowedUnfreePackages = [
    # System76 hardware
    "system76-wallpapers"
    "system76-wallpapers-0-unstable-2024-04-26"

    # NVIDIA drivers
    "nvidia-x11"
    "nvidia-settings"

    # Development tools
    "code"
    "vscode"
    "vscode-fhs"

    # Archive utilities
    "p7zip-rar"
    "rar"
    "unrar"
  ];

  configurations.nixos.system76.module =
    { pkgs, ... }:
    {
      environment.systemPackages = lib.mkAfter (
        with pkgs;
        [
          # System76 hardware utilities
          system76-power
          system76-scheduler
          system76-firmware
          system76-wallpapers
          firmware-manager
          system76-keyboard-configurator

          # PipeWire controls for selecting outputs and adjusting volume
          pwvucontrol
          qpwgraph
          helvum

          # Audio production and codecs
          alsa-utils
          gst_all_1.gstreamer
          gst_all_1.gst-plugins-base
          gst_all_1.gst-plugins-good
          gst_all_1.gst-plugins-bad
          gst_all_1.gst-plugins-ugly

          # Diagnostics and stress testing utilities for crash triage
          lm_sensors
          smartmontools
          nvme-cli
          stress-ng
          memtester
          glmark2
          hwinfo
        ]
      );
    };
}
