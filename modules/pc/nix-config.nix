{
  flake.modules.nixos.pc.nix = {
    # Enable experimental features system-wide
    settings.experimental-features = [
      "nix-command"
      "flakes"
      "pipe-operators"
    ];

    # Keep existing optimizations
    settings = {
      auto-optimise-store = false; # Can be enabled if desired
      cores = 0; # Use all available cores
      max-jobs = "auto"; # Automatic job count
    };
  };
}
