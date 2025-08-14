{ lib, ... }:
{
  flake.modules.nixos.boot-redundancy =
    { config, ... }:
    {
      boot.loader.grub.mirroredBoots =
        config.storage.redundancy.range
        |> lib.map (i: [
          {
            devices = [ "nodev" ];
            path = "/boot${i}";
          }
        ])
        |> lib.mkMerge;

      fileSystems =
        config.storage.redundancy.range
        |> lib.map (i: {
          "/boot${i}" = {
            device = "/dev/disk/by-partlabel/boot${i}";
            fsType = "vfat";
            options = [
              "fmask=0022"
              "dmask=0022"
            ];
          };
        })
        |> lib.mkMerge;
    };
}
