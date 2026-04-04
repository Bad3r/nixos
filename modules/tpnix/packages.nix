{ lib, ... }:
{
  nixpkgs.allowedUnfreePackages = [
    # NVIDIA drivers
    "nvidia-settings"
    "nvidia-x11"

    # Development tools
    "code"
    "vscode"
    "vscode-fhs"

    # Archive utilities
    "p7zip-rar"
    "rar"
    "unrar"
  ];

  configurations.nixos.tpnix.module =
    { pkgs, ... }:
    {
      environment.systemPackages = lib.mkAfter (
        with pkgs;
        [
          # Firmware tooling
          firmware-manager

          # PipeWire controls for selecting outputs and adjusting volume
          pwvucontrol
          qpwgraph

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
