{ config, lib, ... }:
{
  configurations.nixos.songbird.module = {
    home-manager.sharedModules = lib.mkAfter [
      config.flake.homeManagerModules.passSecretServiceBackend
    ];
  };
}
