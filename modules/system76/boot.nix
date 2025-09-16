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

        # Initrd modules (none required explicitly here)
        initrd.kernelModules = [ ];

        # CPU virtualization
        kernelModules = [ "kvm-intel" ];

        # Blacklist nouveau to avoid conflicts with proprietary NVIDIA driver
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
