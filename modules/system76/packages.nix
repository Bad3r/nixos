# Module: system76/packages.nix
# Purpose: System and user package configuration
# Namespace: flake.modules.configurations
# Pattern: Host configuration - System-specific settings and hardware

# System76-specific packages
{ config, ... }:
{
  configurations.nixos.system76.module = { pkgs, lib, ... }: {
    environment.systemPackages = with pkgs; [
      # System76 hardware utilities
      system76-power
      system76-scheduler
      firmware-manager
      system76-keyboard-configurator
    ];
  };
}