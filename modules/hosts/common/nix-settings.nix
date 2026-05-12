{ lib, ... }:
let
  body = {
    nix.settings = {
      experimental-features = lib.mkDefault [
        "nix-command"
        "flakes"
        "pipe-operators"
      ];
      auto-optimise-store = lib.mkDefault true;
      cores = lib.mkDefault 0;
    };
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
