{
  flake.modules.nixos.base = {
    boot.initrd.compressor = "zstd";
  };
}