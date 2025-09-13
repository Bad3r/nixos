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
          ];

          # LUKS encryption for devices
          luks.devices = {
            # Root device
            "luks-251cdcdc-bbb7-4530-8c77-f6d14071bb2d".device =
              "/dev/disk/by-uuid/251cdcdc-bbb7-4530-8c77-f6d14071bb2d";

            # Swap device (encrypted)
            "luks-42ddd341-f150-4d0e-b5a9-d3f209688b64".device =
              "/dev/disk/by-uuid/42ddd341-f150-4d0e-b5a9-d3f209688b64";
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
          device = "/dev/disk/by-uuid/7ea955bc-9272-4ffb-9b10-0537e812f31e";
          fsType = "ext4";
        };
        "/boot" = {
          device = "/dev/disk/by-uuid/13EA-A8F2";
          fsType = "vfat";
          options = [
            "fmask=0077"
            "dmask=0077"
          ];
        };
      };

      # Swap device (references the decrypted swap UUID)
      swapDevices = [ { device = "/dev/disk/by-uuid/03000410-3fba-4651-b5ae-70c1b470be8c"; } ];

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
