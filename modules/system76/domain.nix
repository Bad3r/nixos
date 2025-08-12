# Module: system76/domain.nix
# Purpose: Network configuration and management
# Namespace: flake.modules.configurations
# Pattern: Host configuration - System-specific settings and hardware

{
  configurations.nixos.system76.module = {
    networking.domain = "local";
  };
}