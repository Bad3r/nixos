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
      throw ("Unknown NixOS app '" + name + "' (role system.nixos)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);
  nixosApps = [
    "nixos-build-vms"
    "nixos-configuration-reference-manpage"
    "nixos-enter"
    "nixos-firewall-tool"
    "nixos-generate-config"
    "nixos-help"
    "nixos-icons"
    "nixos-install"
    "nixos-manual-html"
    "nixos-option"
    "nixos-rebuild-ng"
    "nixos-version"
  ];
  roleImports = getApps nixosApps;
in
{
  flake.nixosModules.roles.system.nixos = {
    metadata = {
      canonicalAppStreamId = "System";
      categories = [ "System" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = roleImports;
  };
}
