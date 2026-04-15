{ lib, ... }:
{
  configurations.nixos.tpnix.module =
    { config, ... }:
    {
      hardware.enableRedistributableFirmware = lib.mkForce true;
      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
      hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

      boot = {
        initrd = {
          availableKernelModules = [
            "xhci_pci"
            "thunderbolt"
            "nvme"
            "usbhid"
            "usb_storage"
            "sd_mod"
            "sdhci_pci"
          ];
          kernelModules = [ ];
          luks = {
            devices = {
              "luks-dc8e394e-d685-429e-b256-3b803635b47d".device =
                "/dev/disk/by-uuid/dc8e394e-d685-429e-b256-3b803635b47d";
              "luks-df7db70f-8965-4516-976d-8fdac91ae660".device =
                "/dev/disk/by-uuid/df7db70f-8965-4516-976d-8fdac91ae660";
            };
          };
        };
        kernelModules = [ "kvm-intel" ];
        extraModulePackages = [ ];
      };

      fileSystems = {
        "/" = {
          device = "/dev/mapper/luks-dc8e394e-d685-429e-b256-3b803635b47d";
          fsType = "ext4";
        };
        "/boot" = {
          device = "/dev/disk/by-uuid/1F94-C5D7";
          fsType = "vfat";
          options = [
            "fmask=0077"
            "dmask=0077"
          ];
        };
      };

      swapDevices = [
        {
          device = "/dev/mapper/luks-df7db70f-8965-4516-976d-8fdac91ae660";
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
