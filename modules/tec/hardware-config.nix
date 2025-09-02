{ config, ... }:
{
  configurations.nixos.tec.module =
    { pkgs, lib, ... }:
    {
      # Platform configuration (required)
      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

      # CPU microcode updates
      hardware.cpu.intel.updateMicrocode = lib.mkDefault true;

      # Kernel modules from nixos-generate-config
      boot.initrd.availableKernelModules = [
        "xhci_pci"
        "thunderbolt"
        "nvme"
        "uas"
        "usb_storage"
        "usbhid"
        "sd_mod"
      ];
      boot.initrd.kernelModules = [ ];
      boot.kernelModules = [ "kvm-intel" ];
      boot.extraModulePackages = [ ];

      # Enable Bluetooth
      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
        settings = {
          General = {
            Experimental = true;
            KernelExperimental = true;
          };
        };
      };

      # Enable NTFS support
      boot.supportedFilesystems = [ "ntfs" ];

      # Boot loader configuration
      boot.loader = {
        systemd-boot = {
          enable = true;
          editor = false;
          consoleMode = "auto";
          configurationLimit = 3;
        };
        efi.canTouchEfiVariables = true;
      };

      # Filesystem configuration
      fileSystems = {
        "/" = {
          device = "/dev/disk/by-uuid/e368affc-9d20-4b80-a45f-ff517e126aed";
          fsType = "ext4";
        };
        "/boot" = {
          device = "/dev/disk/by-uuid/538E-2B1B";
          fsType = "vfat";
          options = [
            "fmask=0077"
            "dmask=0077"
          ];
        };
      };

      # LUKS encryption for root device
      boot.initrd.luks.devices."luks-29c517ce-ea2a-416e-8340-223deda4aacf".device =
        "/dev/disk/by-uuid/29c517ce-ea2a-416e-8340-223deda4aacf";

      # Swap device
      swapDevices = [ { device = "/dev/disk/by-uuid/49b87403-5321-493f-8dc8-4a9ff5333c5a"; } ];
    };
}
