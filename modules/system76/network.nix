# Module: system76/network.nix
# Purpose: Network configuration and management
# Namespace: flake.modules.configurations
# Pattern: Host configuration - System-specific settings and hardware

# Network configuration for System76
{ config, ... }:
{
  configurations.nixos.system76.module = { pkgs, lib, ... }: {
    # Networking
    networking = {
      networkmanager.enable = true;
      firewall = {
        enable = true;
        allowedTCPPorts = [ 22 ]; # SSH if needed
      };
    };
  };
}