_: {
  configurations.nixos.system76.module =
    { lib, ... }:
    {
      # Platform configuration (required)
      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

      # Hardware configuration
      hardware = {
        # CPU microcode updates
        cpu.intel.updateMicrocode = lib.mkDefault true;

        # Enable Bluetooth
        bluetooth = {
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
        sane = {
          enable = false;
          # extraBackends = with pkgs; [
          #   sane-airscan
          #   hplipWithPlugin  # Requires unfree license
          # ];
        };
      };

      # Boot configuration
      boot = {
        # Kernel modules and initrd configuration
        initrd = {
          availableKernelModules = [
            "xhci_pci"
            "ahci"
            "nvme"
            "usbhid"
            "usb_storage"
            "sd_mod"
            "sdhci_pci"
            "ext4" # Explicitly ensure ext4 module is available for root filesystem
          ];

          # LUKS encryption for devices
          luks.devices = {
            # Root device
            "luks-de5ef033-553b-4943-be41-09125eb815b2".device =
              "/dev/disk/by-uuid/de5ef033-553b-4943-be41-09125eb815b2";

            # Swap device (CRITICAL FIX - was missing)
            "luks-555de4f1-f4b6-4fd1-acd2-9d735ab4d9ec".device =
              "/dev/disk/by-uuid/555de4f1-f4b6-4fd1-acd2-9d735ab4d9ec";
          };
        };

        kernelModules = [ "kvm-intel" ];

        # Enable NTFS support
        supportedFilesystems = [ "ntfs" ];

        # Boot loader configuration (CRITICAL - must be here for system to boot)
        loader = {
          systemd-boot = {
            enable = true;
            editor = false;
            consoleMode = "auto";
            configurationLimit = 3;
          };
          efi.canTouchEfiVariables = true;
        };
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
