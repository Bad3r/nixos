{
  configurations.nixos.tpnix.module.nix.settings = {
    max-jobs = 2;
    max-substitution-jobs = 7; # nproc - 1 (Tiger Lake 4C/8T)
    min-free = 8589934592; # 8 GiB
  };
}
