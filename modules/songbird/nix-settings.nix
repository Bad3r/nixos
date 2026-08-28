_: {
  configurations.nixos.songbird.module.nix.settings = {
    max-jobs = "auto"; # 8P + 16E cores, 48 GB RAM
    max-substitution-jobs = 23; # nproc - 1 (24 threads)
    min-free = 53687091200; # 50GB - trigger GC when less than this
  };
}
