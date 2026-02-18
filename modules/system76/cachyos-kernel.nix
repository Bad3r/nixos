/*
  CachyOS kernel configuration for System76.
  Provides optimized kernel with BORE scheduler and performance patches.

  Source: https://github.com/xddxdd/nix-cachyos-kernel
*/
{ inputs, lib, ... }:
let
  cachyosSubstituter = "https://attic.xuyh0120.win/lantian";
  cachyosPublicKey = "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=";
in
{
  configurations.nixos.system76.module = {
    # Add CachyOS kernel overlay with pinned package definitions.
    nixpkgs.overlays = [ inputs.nix-cachyos-kernel.overlays.pinned ];

    # Enable CachyOS kernel binary cache only for hosts using this module.
    nix.settings.extra-substituters = lib.mkAfter [ cachyosSubstituter ];
    nix.settings.extra-trusted-public-keys = lib.mkAfter [ cachyosPublicKey ];
  };
}
