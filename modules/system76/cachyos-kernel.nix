/*
  CachyOS kernel configuration for System76.
  Provides optimized kernel with BORE scheduler and performance patches.

  Source: https://github.com/xddxdd/nix-cachyos-kernel
*/
{ inputs, lib, ... }:
{
  configurations.nixos.system76.module = {
    # Add CachyOS kernel overlay (pinned versions for binary cache)
    nixpkgs.overlays = [ inputs.nix-cachyos-kernel.overlays.pinned ];

    # Binary cache for pre-built CachyOS kernels (low priority - only has kernels)
    nix.settings = {
      substituters = lib.mkAfter [ "https://attic.xuyh0120.win/lantian" ];
      trusted-public-keys = lib.mkAfter [ "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=" ];
    };
  };
}
