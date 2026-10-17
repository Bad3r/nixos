{ lib, ... }:
let
  body =
    { pkgs, ... }:
    {
      environment.systemPackages = lib.mkAfter (
        with pkgs;
        [
          # ALSA mixer and playback tools
          alsa-utils

          # Diagnostics and stress testing utilities for crash triage
          lm_sensors
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
