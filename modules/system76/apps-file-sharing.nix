{ config, lib, ... }:
let
  getAppModule =
    name:
    let
      path = [
        "flake"
        "nixosModules"
        "apps"
        name
      ];
    in
    lib.attrByPath path (throw "Missing NixOS app '${name}' while wiring System76 file sharing tools.")
      config;

  getApps = config.flake.lib.nixos.getApps or (names: map getAppModule names);

  fileSharingAppNames = [
    "qbittorrent"
    "localsend"
    "rclone"
    "rsync"
    "nicotine"
    "filen-cli"
    "filen-desktop"
    "dropbox"
  ];
in
{
  configurations.nixos.system76.module.imports = getApps fileSharingAppNames;
}
