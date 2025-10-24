{ config, lib, ... }:
let
  getAppModule =
    name:
    let
      path = [
        "flake"
        "nixosModules"
        "apps"
        name
      ];
    in
    lib.attrByPath path (throw "Missing NixOS app '${name}' while wiring System76 file utilities.")
      config;

  getApps = config.flake.lib.nixos.getApps or (names: map getAppModule names);

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
