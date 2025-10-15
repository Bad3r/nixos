{ lib, ... }:
let
  nixConfigModule = _: {
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
in
{
  flake.lib.roleExtras = lib.mkAfter [
    {
      role = "system.nixos";
      modules = [ nixConfigModule ];
    }
  ];
}
