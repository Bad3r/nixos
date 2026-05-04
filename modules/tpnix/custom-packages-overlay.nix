{ config, ... }:
{
  configurations.nixos.tpnix.module = {
    nixpkgs.overlays = [
      config.flake.lib.customPackagesOverlay
    ];
  };
}
