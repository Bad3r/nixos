{ lib, ... }:
{
  flake.nixosModules.base = {
    # Replicate critical functionality from installer/scan/not-detected.nix
    # This module is essential for hardware detection and proper boot

    # Boot configuration for filesystem support and hardware detection
    boot = {
      # Ensure all filesystem drivers are available in initrd
      initrd.includeDefaultModules = true;

      # Enable support for common filesystems
      supportedFilesystems = [
        "ext4"
        "btrfs"
        "xfs"
        "vfat"
      ];
    };

    # Hardware firmware configuration
    # Fully selective approach: firmware is declared explicitly per-host
    # This avoids pulling unnecessary firmware packages
    hardware = {
      enableRedistributableFirmware = lib.mkDefault true;
      enableAllFirmware = false;
    };

    # CPU microcode is provided by explicit CPU-family hardware modules.

  };
}
