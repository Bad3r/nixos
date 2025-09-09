{ config, ... }:
{
  flake.homeManagerModules.base = _args: {
    home = {
      inherit (config.flake.lib.meta.owner) username;
      homeDirectory = "/home/${config.flake.lib.meta.owner.username}";
    };
    programs.home-manager.enable = true;
    systemd.user.startServices = "sd-switch";
  };
}
