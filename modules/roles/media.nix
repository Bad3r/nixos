{ config, lib, ... }:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' (role media)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);
  mediaApps = [
    "mpv"
    "vlc"
    "okular"
    "gwenview"
    "spectacle"
  ];
  roleImports =
    getApps mediaApps
    # Non-app import: include curated media defaults when available.
    ++ lib.optional (config.flake.nixosModules ? media) config.flake.nixosModules.media;
in
{
  flake.nixosModules.roles.media.imports = roleImports;
  flake.nixosModules."role-media".imports = roleImports;
}
