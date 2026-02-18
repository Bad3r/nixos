_: {
  configurations.nixos.system76.module =
    {
      config,
      lib,
      pkgs,
      metaOwner,
      ...
    }:
    let
      owner = metaOwner.username;
      ownerCfg = lib.attrByPath [ "users" "users" owner ] { } config;
      ownerGroup = ownerCfg.group or owner;
    in
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

        # Explicit firmware for Oryx Pro (oryp4) - selective approach
        # Verified via: dmesg | grep -i firmware
        firmware = lib.mkAfter [
          pkgs.linux-firmware # Intel 8265 WiFi (8265-36.ucode), Bluetooth (ibt-12-16.sfi), i915 GPU (kbl_dmc)
          pkgs.sof-firmware # Intel audio DSP (fallback for internal audio)
          pkgs.wireless-regdb # WiFi regulatory database
        ];
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
          luks = {
            # Reuse the first entered passphrase to unlock all LUKS devices
            reusePassphrases = true;

            devices = {
              # Root device
              "luks-251cdcdc-bbb7-4530-8c77-f6d14071bb2d".device =
                "/dev/disk/by-uuid/251cdcdc-bbb7-4530-8c77-f6d14071bb2d";

              # Swap device (encrypted)
              "luks-42ddd341-f150-4d0e-b5a9-d3f209688b64".device =
                "/dev/disk/by-uuid/42ddd341-f150-4d0e-b5a9-d3f209688b64";

              # Data device on SATA SSD (LUKS2 over XFS)
              data = {
                device = "/dev/disk/by-uuid/183d1f98-e95d-4d6c-89de-cbed409bd9a0";
                allowDiscards = true; # enable TRIM passthrough for SSD
              };
            };
          };
        };

        # Enable filesystem support
        supportedFilesystems = [
          "ntfs"
          "xfs"
        ];

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

        # Mount for encrypted XFS volume on /dev/sda1 (via /dev/mapper/data)
        "/data" = {
          device = "/dev/disk/by-uuid/66f87ae8-7a0a-4b98-9c7e-78d72bde1e5c";
          fsType = "xfs";
          options = [
            "noatime"
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

      # Ensure mountpoint exists declaratively
      systemd.tmpfiles.rules = [
        "d /data 0755 ${owner} ${ownerGroup} -"
      ];

      systemd.services."data-ownership" = {
        description = "Ensure /data ownership matches primary user";
        wantedBy = [ "multi-user.target" ];
        after = [ "data.mount" ];
        requires = [ "data.mount" ];
        unitConfig.RequiresMountsFor = [ "/data" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.coreutils}/bin/chown ${owner}:${ownerGroup} /data";
        };
      };

    };
}
