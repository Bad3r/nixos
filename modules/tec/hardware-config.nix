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
        "usbhid"
        "usb_storage"
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
          device = "/dev/disk/by-uuid/d0d73e02-1e44-4238-8000-80c094bd8197";
          fsType = "ext4";
        };
        "/boot" = {
          device = "/dev/disk/by-uuid/E12E-D274";
          fsType = "vfat";
          options = [
            "fmask=0077"
            "dmask=0077"
          ];
        };
      };

      # LUKS encryption for root device
      boot.initrd.luks.devices."luks-cc8bbfe7-0728-4b81-b820-f591249497bd".device =
        "/dev/disk/by-uuid/cc8bbfe7-0728-4b81-b820-f591249497bd";

      # Additional LUKS device from configuration.nix
      boot.initrd.luks.devices."luks-a08024b1-ea03-4826-9f6d-a4ed89ad0448".device =
        "/dev/disk/by-uuid/a08024b1-ea03-4826-9f6d-a4ed89ad0448";

      # Swap device
      swapDevices = [ { device = "/dev/disk/by-uuid/9cd8cdee-8a7f-4973-af17-75bb89579cd6"; } ];
    };
}
