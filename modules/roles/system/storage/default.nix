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
      throw ("Unknown NixOS app '" + name + "' (role system.storage)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);

  storageApps = [
    "ddrescue"
    "testdisk"
    "parted"
    "gparted"
    "ventoy-full"
    "ventoy"
    "ntfs3g"
    "hdparm"
    "nvme-cli"
    "smartmontools"
    "f3"
    "gnome-disk-utility"
    "dust"
    "duf"
    "dua"
    "filezilla"
  ];
  roleImports = getApps storageApps;
in
{
  flake.nixosModules.roles.system.storage = {
    metadata = {
      canonicalAppStreamId = "System";
      categories = [ "System" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = roleImports;
  };
}
