{ config, lib, ... }:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' (role gaming)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);
  gamingApps = [
    "steam"
    "wine-tools"
    "mangohud"
    "lutris"
  ];
  roleImports = getApps gamingApps;
in
{
  flake.nixosModules.roles.gaming.imports = roleImports;
  flake.nixosModules."role-gaming".imports = roleImports;
}
