{ lib, ... }:
{
  flake.nixosModules.pc = _: {
    nix.settings = {
      # Force exact order to ensure mirrors are tried before cache.nixos.org
      substituters = lib.mkForce [
        "https://mirrors.sjtug.sjtu.edu.cn/nix-channels/store"
        "https://mirror.sjtu.edu.cn/nix-channels/store"
        "https://cache.nixos.org/"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [ "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" ];
    };
  };
}
