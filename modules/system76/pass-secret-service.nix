{ config, lib, ... }:
{
  configurations.nixos.system76.module = {
    home-manager.sharedModules = lib.mkAfter [
      config.flake.homeManagerModules.passSecretServiceBackend
      config.flake.homeManagerModules.passGpgBootstrap
    ];
  };
}
