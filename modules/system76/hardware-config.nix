{ config, ... }:
{
  configurations.nixos.system76.module =
    { pkgs, lib, ... }:
    {
      # Platform configuration (required)
      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

      # CPU microcode updates
      hardware.cpu.intel.updateMicrocode = lib.mkDefault true;

      # Kernel modules from nixos-generate-config
      boot.initrd.availableKernelModules = [
        "xhci_pci"
        "ahci"
        "nvme"
        "usbhid"
        "usb_storage"
        "sd_mod"
        "sdhci_pci"
        "ext4" # Explicitly ensure ext4 module is available for root filesystem
      ];
      boot.kernelModules = [ "kvm-intel" ];

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

      # Scanner support disabled (hplip requires unfree license)
      hardware.sane = {
        enable = false;
        # extraBackends = with pkgs; [
        #   sane-airscan
        #   hplipWithPlugin  # Requires unfree license
        # ];
      };

      # Enable NTFS support
      boot.supportedFilesystems = [ "ntfs" ];

      # Boot loader configuration (CRITICAL - must be here for system to boot)
      boot.loader = {
        systemd-boot = {
          enable = true;
          editor = false;
          consoleMode = "auto";
          configurationLimit = 3;
        };
        efi.canTouchEfiVariables = true;
      };

      # Filesystem configuration (CRITICAL - must be here for system to boot)
      fileSystems = {
        "/" = {
          device = "/dev/disk/by-uuid/54df1eda-4dc3-40d0-a6da-8d1d7ee612b2";
          fsType = "ext4";
        };
        "/boot" = {
          device = "/dev/disk/by-uuid/98A9-C26F";
          fsType = "vfat";
          options = [
            "fmask=0077"
            "dmask=0077"
          ];
        };
      };

      # LUKS encryption for root device
      boot.initrd.luks.devices."luks-de5ef033-553b-4943-be41-09125eb815b2".device =
        "/dev/disk/by-uuid/de5ef033-553b-4943-be41-09125eb815b2";

      # LUKS encryption for swap device (CRITICAL FIX - was missing)
      boot.initrd.luks.devices."luks-555de4f1-f4b6-4fd1-acd2-9d735ab4d9ec".device =
        "/dev/disk/by-uuid/555de4f1-f4b6-4fd1-acd2-9d735ab4d9ec";

      # Swap device (references the decrypted swap UUID)
      swapDevices = [ { device = "/dev/disk/by-uuid/72b0d736-e0c5-4f72-bc55-f50f7492ceef"; } ];

      # Enable touchpad support
      services.libinput = {
        enable = true;
        touchpad = {
          tapping = true;
          middleEmulation = true;
          naturalScrolling = true;
        };
      };
    };
}
