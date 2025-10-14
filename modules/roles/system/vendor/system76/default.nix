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
      throw ("Unknown NixOS app '" + name + "' (role system.vendor.system76)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);

  supportModule = lib.attrByPath [ "system76-support" ] config.flake.nixosModules null;
  system76Apps = [
    "system76-power"
    "system76-scheduler"
    "system76-firmware"
    "system76-wallpapers"
    "system76-keyboard-configurator"
    "firmware-manager"
    "pavucontrol"
    "qpwgraph"
    "helvum"
    "nvidia-settings"
    "nvidia-x11"
    "vulkan-tools"
    "mesa-demos"
  ];
  roleImports = lib.optional (supportModule != null) supportModule ++ getApps system76Apps;
in
{
  flake.nixosModules.roles.system.vendor.system76 = {
    metadata = {
      canonicalAppStreamId = "System";
      categories = [
        "System"
        "Settings"
      ];
      auxiliaryCategories = [ "Utility" ];
      secondaryTags = [
        "hardware-integration"
        "vendor-system76"
      ];
    };
    imports = roleImports;
  };
}
