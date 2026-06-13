/*
  CachyOS kernel configuration for System76.
  Provides optimized kernel with BORE scheduler and performance patches.

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

  normalizePinnedKernel =
    kernel:
    kernel.overrideAttrs (
      old:
      let
        passthru = old.passthru or { };
      in
      {
        passthru = passthru // {
          # The pinned CachyOS packages are x86_64 kernels built from the
          # input's nixpkgs. Preserve the passthru attrs expected by this
          # repo's NixOS modules without changing the kernel derivation.
          buildDTBs = passthru.buildDTBs or false;
          target = passthru.target or "bzImage";
        };
      }
    );

  normalizePinnedKernelPackages =
    kernelPackages:
    kernelPackages.extend (
      _final: prev: {
        kernel = normalizePinnedKernel prev.kernel;
      }
    );

  cachyosOverlay =
    final: prev:
    let
      pinned = inputs.nix-cachyos-kernel.overlays.pinned final prev;
    in
    pinned
    // {
      cachyosKernels = lib.mapAttrs (
        _: value:
        if lib.isAttrs value && value ? extend && value ? kernel then
          normalizePinnedKernelPackages value
        else
          value
      ) pinned.cachyosKernels;
    };
in
{
  configurations.nixos.system76.module = {
    # Add CachyOS kernel overlay with pinned package definitions.
    nixpkgs.overlays = [ cachyosOverlay ];

    nix.settings = {
      # Enable CachyOS kernel binary caches only for hosts using this module.
      extra-substituters = lib.mkAfter cachyosSubstituters;
      extra-trusted-public-keys = lib.mkAfter cachyosPublicKeys;

      # Lantian's attic offloads NAR chunks to Telnyx Object Storage, which
      stalled-download-timeout = 900;
    };
  };
}
