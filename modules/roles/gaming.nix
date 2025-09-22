{ config, lib, ... }:
let
  helpers = config._module.args.nixosAppHelpers or { };
  hasApp = helpers.hasApp or (name: lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules);
  defaultGetApp =
    name:
    if hasApp name then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' (role gaming)");
  getApp = helpers.getApp or defaultGetApp;
  desiredApps = [
    "steam"
    "wine-tools"
    "mangohud"
    "lutris"
  ];
  availableApps = lib.filter hasApp desiredApps;
  missingApps = lib.filter (app: !(hasApp app)) desiredApps;
  roleImports = map getApp availableApps;
in
{
  flake.nixosModules.roles.gaming.imports = roleImports;
  _module.args._roleGamingMissingApps = missingApps;
}
