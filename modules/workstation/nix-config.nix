_: {
  flake.nixosModules.roles.system.nixos.imports = [
    (_: {
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
    })
  ];
}
