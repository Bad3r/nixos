/*
  CachyOS kernel integration for tpnix.
  Keeps CachyOS overlay/cache available as an optional module while
  allowing the host to select a different active kernel package.

  Source: https://github.com/xddxdd/nix-cachyos-kernel
*/
{ inputs, lib, ... }:
let
  cachyosSubstituter = "https://attic.xuyh0120.win/lantian";
  cachyosPublicKey = "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=";
in
{
  configurations.nixos.tpnix.module = {
    # Keep CachyOS overlay definitions available for optional use.
    nixpkgs.overlays = [ inputs.nix-cachyos-kernel.overlays.pinned ];

    # Keep CachyOS cache keys available when optional packages are selected.
    nix.settings.extra-substituters = lib.mkAfter [ cachyosSubstituter ];
    nix.settings.extra-trusted-public-keys = lib.mkAfter [ cachyosPublicKey ];
  };
}
