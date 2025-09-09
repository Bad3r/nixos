{ lib, ... }:
{
  flake.nixosModules.swap =
    { config, ... }:
    {
      swapDevices = lib.map (n: {
        device = "/dev/disk/by-partlabel/swap${n}";
        randomEncryption.enable = true;
      }) config.storage.redundancy.range;
    };
}
