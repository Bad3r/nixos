{ config, ... }:
{
  nixpkgs.allowedUnfreePackages = [
    "system76-wallpapers"
    "system76-wallpapers-0-unstable-2024-04-26"
  ];

  configurations.nixos.system76.module =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = with pkgs; [
        # System76 hardware utilities
        system76-power
        system76-scheduler
        system76-firmware
        system76-wallpapers
        firmware-manager
        system76-keyboard-configurator
        
        # Additional system-specific tools
        ktailctl  # KDE Tailscale GUI
        localsend  # Local network file sharing
        
        # Additional CLI tools for this system
        httpx
        curlie
        tor
        gpg-tui
        gopass
      ];
    };
}
