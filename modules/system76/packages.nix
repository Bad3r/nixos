{ lib, ... }:
{
  nixpkgs.allowedUnfreePackages = [
    "system76-wallpapers"
    "system76-wallpapers-0-unstable-2024-04-26"
    "nvidia-x11"
    "nvidia-settings"
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
          # Shell prompt
          starship

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
        ]
      );
    };
}
