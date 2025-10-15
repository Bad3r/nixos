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
      throw ("Unknown NixOS app '" + name + "' (role utility.archive)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);

  archiveApps = [
    "zip"
    "unzip"
    "p7zip"
    "p7zip-rar"
    "rar"
    "unrar"
    "tar"
    "gzip"
    "bzip2"
    "xz"
    "zstd"
  ];
  roleImports = getApps archiveApps;
  roleExtraEntries = config.flake.lib.roleExtras or [ ];
  extraModulesForRole = lib.concatMap (
    entry: if (entry ? role) && entry.role == "utility.archive" then entry.modules else [ ]
  ) roleExtraEntries;
  finalImports = roleImports ++ extraModulesForRole;
in
{
  flake.nixosModules.roles.utility.archive = {
    metadata = {
      canonicalAppStreamId = "Utility";
      categories = [ "Utility" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = finalImports;
  };
}
