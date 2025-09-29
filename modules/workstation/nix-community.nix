{ lib, ... }:
let
  substitutersList = [
    "https://cache.garnix.io"
    "https://mirrors.sjtug.sjtu.edu.cn/nix-channels/store"
    "https://mirror.sjtu.edu.cn/nix-channels/store"
    "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
    "https://cache.nixos.org/"
  ];
  trustedKeys = [
    "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
  ];
in
{
  flake.nixosModules.workstation = _: {
    nix.settings = {
      # Force exact order so mirrors are attempted before cache.nixos.org
      substituters = lib.mkForce substitutersList;
      trusted-public-keys = trustedKeys;
      narinfo-cache-negative-ttl = 0;
      http-connections = 25;
      http2 = true;
    };
  };
}
