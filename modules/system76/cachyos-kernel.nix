/*
  CachyOS kernel configuration for System76.
  Provides optimized kernel with BORE scheduler and performance patches.

  Source: https://github.com/xddxdd/nix-cachyos-kernel
*/
{ inputs, ... }:
{
  configurations.nixos.system76.module = {
    # Add CachyOS kernel overlay with pinned package definitions.
    nixpkgs.overlays = [ inputs.nix-cachyos-kernel.overlays.pinned ];
  };
}
