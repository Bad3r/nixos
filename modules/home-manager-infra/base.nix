# Module: home-manager-infra/base.nix
# Purpose: Base configuration
# Namespace: flake.modules.homeManager.base
# Pattern: Home Manager base - CLI and terminal environment

{ config, ... }:
{
  flake.modules.homeManager.base = args: {
    home = {
      username = config.flake.meta.owner.username;
      homeDirectory = "/home/${config.flake.meta.owner.username}";
    };
    programs.home-manager.enable = true;
    systemd.user.startServices = "sd-switch";
  };
}
