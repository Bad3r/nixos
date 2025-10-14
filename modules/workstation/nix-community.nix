{ lib, ... }:
let
  nixCommunityModule =
    { lib, ... }:
    let
      substitutersList = [
        "https://mirror.sjtu.edu.cn/nix-channels/store"
        "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
        "https://cache.garnix.io"
        "https://cache.nixos.org/"
      ];
      trustedKeys = [
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
      ];
    in
    {
      nix.settings = {
        substituters = lib.mkForce substitutersList;
        trusted-public-keys = trustedKeys;
        narinfo-cache-negative-ttl = 0;
        http-connections = 25;
        http2 = true;
      };
    };
in
{
  flake.nixosModules.roles.system.nixos.imports = lib.mkAfter [ nixCommunityModule ];
}
