{ config, lib, ... }:
let
  appsDir = ../apps;
  helpers = config._module.args.nixosAppHelpers or { };
  fallbackGetApp =
    name:
    let
      filePath = appsDir + "/${name}.nix";
    in
    if builtins.pathExists filePath then
      let
        exported = import filePath;
        module = lib.attrByPath [
          "flake"
          "nixosModules"
          "apps"
          name
        ] null exported;
      in
      if module != null then
        module
      else
        throw ("NixOS app '" + name + "' missing expected attrpath in " + toString filePath)
    else
      throw ("NixOS app module file not found: " + toString filePath);
  getApp = helpers.getApp or fallbackGetApp;
  getApps = helpers.getApps or (names: map getApp names);

  fileAppNames = [
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
    "ventoy-full"
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
in
{
  configurations.nixos.system76.module.imports = getApps fileAppNames;
}
