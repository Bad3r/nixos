{
  configurations.nixos.system76.module.nix.settings = {
    max-jobs = "auto";
    min-free = 53687091200; # 50GB - trigger GC when less than this
  };
}
