{ config, lib, ... }:
{
  flake.homeManagerModules.base =
    args:
    let
      hmConfig = args.config;
      hmLib = args.lib or lib;
      defaultHome = "/home/${config.flake.lib.meta.owner.username}";
      homeDir = hmConfig.home.homeDirectory or defaultHome;
      sopsServiceHome = "${homeDir}/.local/share/sops-nix";
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

      home.activation.ensureSopsServiceHome = hmLib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p '${sopsServiceHome}'
        chmod 700 '${sopsServiceHome}'
      '';

      systemd.user.services.sops-nix.Service.Environment = lib.mkForce [
        "HOME=${sopsServiceHome}"
      ];
    };
}
