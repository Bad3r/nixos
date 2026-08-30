/*
  CachyOS kernel integration for songbird.

  Nixpkgs does not currently package the CachyOS kernel, so the overlay remains
  an input-specific dependency. No CachyOS substituter is configured here.
*/
{ inputs, ... }:
{
  configurations.nixos.songbird.module =
    { pkgs, ... }:
    {
      nixpkgs.overlays = [ inputs.nix-cachyos-kernel.overlays.pinned ];

      # The generic CachyOS kernel keeps the historical BORE/performance
      # configuration while allowing this host to build it locally.
      boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest;
    };
}
