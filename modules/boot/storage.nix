{ lib, ... }:
{
  flake.modules.nixos.boot-redundancy =
    { config, ... }:
    {
      boot.loader.grub.mirroredBoots = lib.mkMerge (
        lib.map (i: [
          {
            devices = [ "nodev" ];
            path = "/boot${i}";
          }
        ]) config.storage.redundancy.range
      );

      fileSystems = lib.mkMerge (
        lib.map (i: {
          "/boot${i}" = {
            device = "/dev/disk/by-partlabel/boot${i}";
            fsType = "vfat";
            options = [
              "fmask=0022"
              "dmask=0022"
            ];
          };
        }) config.storage.redundancy.range
      );
    };
}
