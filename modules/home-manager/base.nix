{ config, ... }:
{
  flake.homeManagerModules.base = _args: {
    home = {
      inherit (config.flake.lib.meta.owner) username;
      homeDirectory = "/home/${config.flake.lib.meta.owner.username}";
      preferXdgDirectories = true;
    };
    programs.home-manager.enable = true;
    systemd.user.startServices = "sd-switch";
  };
}
