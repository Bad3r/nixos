{
  flake.nixosModules.base = {
    boot.initrd.compressor = "zstd";
  };
}
