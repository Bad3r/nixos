{ lib, ... }:
{
  flake.nixosModules.roles.system.nixos.imports = lib.mkAfter [
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
