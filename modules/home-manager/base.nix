{ config, lib, ... }:
{
  flake.homeManagerModules.base =
    args:
    let
      hmConfig = args.config;
      defaultHome = "/home/${config.flake.lib.meta.owner.username}";
      homeDir = hmConfig.home.homeDirectory or defaultHome;
    in
    {
      home = {
        inherit (config.flake.lib.meta.owner) username;
        homeDirectory = lib.mkDefault defaultHome;
        preferXdgDirectories = true;
      };

      programs.home-manager.enable = true;
      systemd.user.startServices = "sd-switch";

      sops.age.keyFile = lib.mkDefault "${homeDir}/.config/sops/age/keys.txt";
    };
}
