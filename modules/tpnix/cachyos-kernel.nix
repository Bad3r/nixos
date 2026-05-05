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
    "https://attic.xuyh0120.win/lantian?priority=39"
  ];
  cachyosPublicKeys = [
    "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
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
      stalled-download-timeout = 900;
    };
  };
}
