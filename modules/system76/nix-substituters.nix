{ lib, ... }:
let
  substitutersList = [
    # Priority 40 - nixpkgs mirrors (fast, list order determines tiebreaker)
    "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store" # ~1.5 MB/s
    "https://mirror.sjtu.edu.cn/nix-channels/store" # ~1.4 MB/s
    "https://mirrors.ustc.edu.cn/nix-channels/store" # ~1.0 MB/s
    "https://cache.nixos.org/" # ~0.2 MB/s (fallback)
    # Priority 50 - community caches
    "https://cache.garnix.io"
    "https://cache.numtide.com"
  ];
  trustedKeys = [
    "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
    "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
  ];
in
{
  configurations.nixos.system76.module = {
    nix.settings = {
      substituters = substitutersList;
      trusted-public-keys = trustedKeys;
      narinfo-cache-negative-ttl = 10800; # 3 hours
      http-connections = lib.mkForce 0; # unlimited
      http2 = true;
    };
  };
}
