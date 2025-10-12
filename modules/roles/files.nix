{ config, lib, ... }:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' (role files)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);
  fileApps = [
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
    "ddrescue"
    "testdisk"
    "parted"
    "gparted"
    "ventoy-full-gtk"
    "ntfs3g"
    "hdparm"
    "nvme-cli"
    "smartmontools"
    "f3"
    "gnome-disk-utility"
    "iotop"
    "kdiskmark"
    "dust"
    "duf"
    "dua"
    "filezilla"
    "rip2"
    "veracrypt"
  ];
  roleImports = getApps fileApps;
in
{
  flake.nixosModules.roles.files.imports = roleImports;
}
