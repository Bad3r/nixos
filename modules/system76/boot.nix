{ config, ... }:
{
  configurations.nixos.system76.module = { config, pkgs, ... }: {
    boot = {
      # Base kernel modules for System76 hardware
      initrd.availableKernelModules = [
        "xhci_pci"
        "ahci"
        "nvme"
        "usbhid"
        "usb_storage"
        "sd_mod"
        "sdhci_pci"
      ];
      
      # NVIDIA modules to load early
      initrd.kernelModules = [
        "nvidia"
        "nvidia_modeset"
        "nvidia_uvm"
        "nvidia_drm"
      ];
      
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