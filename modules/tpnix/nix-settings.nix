{
  configurations.nixos.tpnix.module.nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
        "pipe-operators"
      ];
      auto-optimise-store = true;
      cores = 0;
      max-jobs = 2;
      min-free = 8589934592; # 8 GiB
    };
  };
}
