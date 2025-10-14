{
  config,
  lib,
  ...
}:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' (role game.launchers)");
  getApp = rawHelpers.getApp or fallbackGetApp;

  launcherApps = [
    "steam"
    "wine-tools"
  ];
  roleImports = map getApp launcherApps;
in
{
  flake.nixosModules.roles.game.launchers = {
    metadata = {
      canonicalAppStreamId = "Game";
      categories = [ "Game" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = roleImports;
  };
}
