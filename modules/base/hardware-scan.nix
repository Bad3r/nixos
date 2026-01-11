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

      # Enable memory test on boot (can be disabled if not needed)
      loader.systemd-boot.memtest86.enable = false;
    };

    # Hardware firmware configuration
    hardware = {
      # Ensure hardware detection happens properly
      enableRedistributableFirmware = true;

      # Enable ALL firmware including non-free for maximum hardware compatibility
      enableAllFirmware = true;
    };

    # CPU microcode is set per-host in hardware-config.nix

    # Permit insecure packages that are required but marked as insecure
    nixpkgs.config.permittedInsecurePackages = [
      "qtwebengine-5.15.19" # Required by some Qt5 applications, marked insecure in NixOS 25.11
    ];
  };
}
