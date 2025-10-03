{ config, lib, ... }:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' (role file-sharing)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);
  fileSharingApps = [
    "qbittorrent"
    "localsend"
    "rclone"
    "rsync"
    "nicotine"
    "filen-cli"
    "filen-desktop"
    "dropbox"
  ];
  roleImports = getApps fileSharingApps;
in
{
  flake.nixosModules.roles."file-sharing".imports = roleImports;
}
