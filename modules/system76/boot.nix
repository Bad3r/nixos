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

        # For dGPU-only: do not include Intel i915 in initrd
        initrd.kernelModules = [ ];

        # CPU virtualization
        kernelModules = [ "kvm-intel" ];

        # Blacklist nouveau and i915 to prevent conflicts and enforce dGPU-only
        blacklistedKernelModules = [
          "nouveau"
          "i915"
        ];

        # NVIDIA kernel parameters
        kernelParams = [
          "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
          "nvidia.NVreg_EnableGpuFirmware=1"
          "module_blacklist=i915"
        ];

        # Add NVIDIA driver to extra module packages
        extraModulePackages = [ config.boot.kernelPackages.nvidia_x11 ];
      };
    };
}
