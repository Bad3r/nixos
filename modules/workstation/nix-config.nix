{
  flake.nixosModules.workstation = _: {
    # Enable experimental features system-wide
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
      "pipe-operators"
    ];

    # Keep existing optimizations
    nix.settings = {
      auto-optimise-store = false;
      cores = 0; # 0 == ALL
      max-jobs = "auto";
    };
  };
}
