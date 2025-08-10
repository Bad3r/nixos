# Module: boot-storage.nix
# Purpose: Configure boot partitions and filesystems for redundancy
# Namespace: flake.modules.nixos.base
# Dependencies: storage-redundancy configuration

{ lib, ... }:
{
  flake.modules.nixos.base = { config, ... }: {
    boot.loader.grub.mirroredBoots =
      config.storage.redundancy.range
      |> map (i: [
        {
          devices = [ "nodev" ];
          path = "/boot${i}";
        }
      ])
      |> lib.mkMerge;

    fileSystems =
      config.storage.redundancy.range
      |> map (i: {
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
