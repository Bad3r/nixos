{ lib, ... }:
let
  substitutersList = [
    "https://mirror.sjtu.edu.cn/nix-channels/store"
    "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
    "https://cache.garnix.io"
    "https://cache.numtide.com"
    "https://cache.nixos.org/"
  ];
  trustedKeys = [
    "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
    "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
  ];
in
{
  configurations.nixos.system76.module = {
    nix.settings = {
      substituters = lib.mkForce substitutersList;
      trusted-public-keys = trustedKeys;
      narinfo-cache-negative-ttl = 10800; # 3 hours
      http-connections = lib.mkForce 0; # unlimited
      http2 = true;
    };
  };
}
