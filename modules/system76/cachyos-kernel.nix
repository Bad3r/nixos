/*
  CachyOS kernel configuration for System76.
  Provides optimized kernel with BORE scheduler and performance patches.

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
  configurations.nixos.system76.module = {
    # Add CachyOS kernel overlay with pinned package definitions.
    nixpkgs.overlays = [ inputs.nix-cachyos-kernel.overlays.pinned ];

    nix.settings = {
      # Enable CachyOS kernel binary caches only for hosts using this module.
      extra-substituters = lib.mkAfter cachyosSubstituters;
      extra-trusted-public-keys = lib.mkAfter cachyosPublicKeys;

      # Lantian's attic offloads NAR chunks to Telnyx Object Storage, which
      stalled-download-timeout = 900;
    };
  };
}
