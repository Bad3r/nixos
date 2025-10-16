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
      throw ("Unknown game tool '" + name + "'");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);
  toolApps = [
    "proton-ge-bin"
    "proton-run"
    "steam-run"
    "wine-staging"
    "wine-wow-staging"
    "winetricks"
  ];
in
{
  flake.nixosModules.roles.game.tools = {
    metadata = {
      canonicalAppStreamId = "Game";
      categories = [ "Game" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = getApps toolApps;
  };
}
