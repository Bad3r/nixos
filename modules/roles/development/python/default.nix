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
      throw ("Unknown NixOS app '" + name + "' (role development.python)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);

  pythonModule =
    let
      path = [
        "lang"
        "python"
      ];
    in
    if lib.hasAttrByPath path config.flake.nixosModules then
      lib.getAttrFromPath path config.flake.nixosModules
    else
      ../../../languages/lang-python.nix;

  pythonApps = [
    "python"
    "uv"
    "ruff"
    "pyright"
  ];
  pythonImports = [ pythonModule ] ++ getApps pythonApps;
  roleExtraEntries = config.flake.lib.roleExtras or [ ];
  extraModulesForRole = lib.concatMap (
    entry: if (entry ? role) && entry.role == "development.python" then entry.modules else [ ]
  ) roleExtraEntries;
  finalImports = pythonImports ++ extraModulesForRole;
in
{
  flake.nixosModules.roles.development.python = {
    metadata = {
      canonicalAppStreamId = "Development";
      categories = [ "Development" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = finalImports;
  };
}
