
{
  flake.modules.nixos.swap =  # Swap is optional storage (not all systems need it)
    { config, ... }:
    {
      swapDevices =
        config.storage.redundancy.range
        |> map (n: {
          device = "/dev/disk/by-partlabel/swap${n}";
          randomEncryption.enable = true;
        });
    };
}
