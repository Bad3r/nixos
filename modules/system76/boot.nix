_: {
  configurations.nixos.system76.module =
    { config, pkgs, ... }:
    {
      # Use latest kernel packages on this host
      boot.kernelPackages = pkgs.linuxPackages_latest;
      boot = {
        # Base kernel modules for System76 hardware
        initrd.availableKernelModules = [
          "xhci_pci"
          "ahci"
          "nvme"
          "thunderbolt"
          "usbhid"
          "uas"
          "usb_storage"
          "sd_mod"
          "sdhci_pci"
        ];

        # CRITICAL FIX: Removed NVIDIA modules from initrd to prevent kernel panic
        # NVIDIA drivers should only load after switch root, not in initrd
        # Only Intel graphics (i915) should be in initrd for PRIME systems
        initrd.kernelModules = [ "i915" ];

        # CPU virtualization
        kernelModules = [ "kvm-intel" ];

        # Blacklist nouveau driver to prevent conflicts
        blacklistedKernelModules = [ "nouveau" ];

        # NVIDIA kernel parameters
        kernelParams = [
          "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
          "nvidia.NVreg_EnableGpuFirmware=1"
        ];

        # Add NVIDIA driver to extra module packages
        extraModulePackages = [ config.boot.kernelPackages.nvidia_x11 ];
      };
    };
}
