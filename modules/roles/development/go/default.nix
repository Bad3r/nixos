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
      throw ("Unknown NixOS app '" + name + "' (role development.go)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);

  goModule =
    let
      path = [
        "lang"
        "go"
      ];
    in
    if lib.hasAttrByPath path config.flake.nixosModules then
      lib.getAttrFromPath path config.flake.nixosModules
    else
      ../../../languages/lang-go.nix;

  goApps = [
    "go"
    "gopls"
    "golangci-lint"
    "delve"
  ];
  goImports = [ goModule ] ++ getApps goApps;
  roleExtraEntries = config.flake.lib.roleExtras or [ ];
  extraModulesForRole = lib.concatMap (
    entry: if (entry ? role) && entry.role == "development.go" then entry.modules else [ ]
  ) roleExtraEntries;
  finalImports = goImports ++ extraModulesForRole;
in
{
  flake.nixosModules.roles.development.go = {
    metadata = {
      canonicalAppStreamId = "Development";
      categories = [ "Development" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = finalImports;
  };
}
