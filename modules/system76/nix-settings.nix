{
  configurations.nixos.system76.module.nix.settings = {
    max-jobs = "auto";
    max-substitution-jobs = 11; # nproc - 1 (i7-8750H, 6C/12T)
    min-free = 53687091200; # 50GB - trigger GC when less than this
  };
}
