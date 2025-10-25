{
  configurations.nixos.system76.module = {
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
      "pipe-operators"
    ];

    nix.settings = {
      auto-optimise-store = true;
      cores = 0;
      max-jobs = "auto";
    };
  };
}
