{
  configurations.nixos.tpnix.module.nix.settings = {
    max-jobs = 2;
    min-free = 8589934592; # 8 GiB
  };
}
