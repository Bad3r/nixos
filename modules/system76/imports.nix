# Import chain: workstation (includes pc→base) + nvidia-gpu

{ config, lib, ... }:
{
  configurations.nixos.system76.module = {
    imports = with config.flake.modules.nixos; [
      # Base system configurations (workstation includes pc→base chain)
      workstation  # This brings in pc → base chain
      
      # Hardware-specific named modules
      nvidia-gpu   # NVIDIA graphics (CORRECT named module per golden standard)
      efi         # UEFI boot support (now a named module)
      swap        # Swap configuration (now a named module)
      
      # Note: home-manager-setup now in base namespace (imported via chain)
      # Note: system76-complete split into focused files that extend this configuration
    ];
  };
}