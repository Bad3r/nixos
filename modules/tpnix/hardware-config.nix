{ lib, ... }:
{
  configurations.nixos.tpnix.module =
    { config, ... }:
    {
      hardware.enableRedistributableFirmware = lib.mkForce true;
      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
      hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

      boot = {
        initrd.availableKernelModules = [
          "xhci_pci"
          "thunderbolt"
          "nvme"
          "usb_storage"
          "sd_mod"
        ];
        initrd.kernelModules = [ ];
        kernelModules = [ "kvm-intel" ];
        extraModulePackages = [ ];

        loader = {
          systemd-boot = {
            enable = true;
            editor = false;
            consoleMode = "auto";
            configurationLimit = 5;
          };
          efi.canTouchEfiVariables = true;
        };
      };

      fileSystems = {
        "/" = {
          device = "/dev/disk/by-uuid/11920378-b861-46d6-b4d8-64a90ce03bbb";
          fsType = "ext4";
        };
        "/boot" = {
          device = "/dev/disk/by-uuid/DC64-2E36";
          fsType = "vfat";
          options = [
            "fmask=0077"
            "dmask=0077"
          ];
        };
      };

      swapDevices = [
        {
          device = "/dev/disk/by-uuid/a9baee3b-5b98-4a80-95c9-0c1cb974b2e9";
        }
      ];

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
