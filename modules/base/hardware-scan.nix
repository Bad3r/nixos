{
  flake.modules.nixos.base = {
    # Replicate critical functionality from installer/scan/not-detected.nix
    # This module is essential for hardware detection and proper boot

    # Ensure all filesystem drivers are available in initrd
    boot.initrd.includeDefaultModules = true;

    # Enable support for common filesystems
    boot.supportedFilesystems = [
      "ext4"
      "btrfs"
      "xfs"
      "vfat"
    ];

    # Ensure hardware detection happens properly
    hardware.enableRedistributableFirmware = true;

    # Enable ALL firmware including non-free for maximum hardware compatibility
    hardware.enableAllFirmware = true;

    # CPU microcode is set per-host in hardware-config.nix

    # Enable memory test on boot (can be disabled if not needed)
    boot.loader.systemd-boot.memtest86.enable = false;

    # Allow unfree firmware packages (required for hardware.enableAllFirmware)
    nixpkgs.config.allowUnfree = true;
  };
}
