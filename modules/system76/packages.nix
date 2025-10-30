{ lib, ... }:
{
  nixpkgs.allowedUnfreePackages = [
    "system76-wallpapers"
    "system76-wallpapers-0-unstable-2024-04-26"
    "nvidia-x11"
    "nvidia-settings"
    "code"
    "vscode"
    "vscode-fhs"
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
          pavucontrol
          qpwgraph
          helvum

          # Audio production and codecs
          alsa-utils
          ardour
          audacity
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
