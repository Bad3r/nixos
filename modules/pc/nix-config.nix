{
  flake.nixosModules.pc.nix = {
    # Enable experimental features system-wide
    settings.experimental-features = [
      "nix-command"
      "flakes"
      "pipe-operators"
    ];

    # Keep existing optimizations
    settings = {
      auto-optimise-store = false;
      cores = 0; # 0 == ALL
      max-jobs = "auto";
    };
  };
}
