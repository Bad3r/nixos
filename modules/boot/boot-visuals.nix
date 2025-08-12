# Module: boot/boot-visuals.nix
# Purpose: Boot Visuals configuration
# Namespace: flake.modules.nixos.boot
# Pattern: Boot configuration - System initialization and bootloader

# modules/boot/boot-visuals.nix
# Boot visuals configuration following golden standard
{
  flake.modules.nixos = {
    base = {
      # Base visual settings for ALL systems
      stylix.targets.grub.enable = false;
      boot.kernelParams = [
        "quiet"
        "systemd.show_status=error"
      ];
    };
    pc = {
      # Plymouth only for desktop/laptop systems (servers don't need it)
      boot.plymouth.enable = true;
    };
  };
}