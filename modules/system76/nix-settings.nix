{
  configurations.nixos.system76.module.nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
        "pipe-operators"
      ];
      auto-optimise-store = true;
      cores = 0;
      max-jobs = "auto";
      min-free = 53687091200; # 50GB - trigger GC when less than this
    };

  };
}
