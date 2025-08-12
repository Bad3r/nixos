# Module: boot/tmp.nix
# Purpose: Temporary filesystem configuration using tmpfs
# Namespace: flake.modules.nixos.boot
# Pattern: Boot configuration - System initialization and bootloader

{
  flake.modules.nixos.base.boot.tmp.cleanOnBoot = true;  # Core system feature
}
