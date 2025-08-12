# Module: system76/state-version.nix
# Purpose: State Version configuration
# Namespace: flake.modules.configurations
# Pattern: Host configuration - System-specific settings and hardware

{
  configurations.nixos.system76.module = {
    system.stateVersion = "25.05";
  };
}