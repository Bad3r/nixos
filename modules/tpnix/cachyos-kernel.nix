/*
  CachyOS kernel integration for tpnix.
  Keeps CachyOS overlay/cache available as an optional module while
  allowing the host to select a different active kernel package.

  Source: https://github.com/xddxdd/nix-cachyos-kernel
*/
{ inputs, lib, ... }:
let
  # Mirrors the substituters declared by nix-cachyos-kernel's flake nixConfig.
  cachyosSubstituters = [
    "https://attic.xuyh0120.win/lantian"
    "https://cache.garnix.io"
  ];
  cachyosPublicKeys = [
    "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
    "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
  ];
in
{
  configurations.nixos.tpnix.module = {
    # Keep CachyOS overlay definitions available for optional use.
    nixpkgs.overlays = [ inputs.nix-cachyos-kernel.overlays.pinned ];

    nix.settings = {
      # Keep CachyOS cache keys available when optional packages are selected.
      extra-substituters = lib.mkAfter cachyosSubstituters;
      extra-trusted-public-keys = lib.mkAfter cachyosPublicKeys;

      # Lantian's attic offloads NAR chunks to Telnyx Object Storage, which
      # can deliver them slowly enough to trip Nix's default stall timeout
      # while fetching large kernel-modules NARs. Give curl more patience.
      connect-timeout = 30;
      stalled-download-timeout = 900;
    };
  };
}
