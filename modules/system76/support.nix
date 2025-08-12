# Module: system76/support.nix
# Purpose: Support configuration
# Namespace: flake.modules.nixos.system76-support
# Pattern: Hardware configuration module

{ ... }:
{
  flake.modules.nixos.system76-support = { pkgs, ... }: {
    hardware.system76.enableAll = true;
    
    environment.systemPackages = with pkgs; [
      system76-firmware
      firmware-manager
      system76-keyboard-configurator
    ];
    
    # System76-specific kernel parameters
    boot.kernelParams = [
      "system76_acpi.brightness_hwmon=1"
    ];
  };
}