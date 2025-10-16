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
      throw ("Unknown NixOS app '" + name + "' (role utility.cli)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);

  cliApps = [
    "dragon-drop"
    "direnv"
    "nix-direnv"
    "cosmic-term"
    "tealdeer"
  ];
  roleImports = getApps cliApps;
  roleExtraEntries = config.flake.lib.roleExtras or [ ];
  extraModulesForRole = lib.concatMap (
    entry: if (entry ? role) && entry.role == "utility.cli" then entry.modules else [ ]
  ) roleExtraEntries;
  finalImports = roleImports ++ extraModulesForRole;
in
{
  flake.nixosModules.roles.utility.cli = {
    metadata = {
      canonicalAppStreamId = "Utility";
      categories = [ "Utility" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = finalImports;
  };
}
