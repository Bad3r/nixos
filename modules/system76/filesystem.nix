{ config, ... }:
{
  configurations.nixos.system76.module = {
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
  };
}