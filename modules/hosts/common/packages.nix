{ lib, ... }:
let
  body =
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
in
{
  # Shared unfree allowlist (contributed at the flake-parts level so the
  # allowUnfreePredicate sees them across both hosts).
  nixpkgs.allowedUnfreePackages = [
    # NVIDIA drivers
    "nvidia-kernel-modules"
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

  flake.nixosModules.hosts-common.imports = [ body ];
}
