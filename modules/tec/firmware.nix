_: {
  configurations.nixos.tec.module = {
    # Enable fwupd for firmware updates via LVFS
    services.fwupd = {
      enable = true;
      # Enable test firmware for devices not yet in stable
      # daemonSettings.TestDevices = true;
    };

    # Ensure latest linux-firmware package
    hardware.enableRedistributableFirmware = true;

    # CPU microcode updates
    hardware.cpu.intel.updateMicrocode = true;
  };
}
