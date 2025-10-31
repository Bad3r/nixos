{ config, ... }:
let
  helpers =
    config._module.args.nixosAppHelpers
      or (throw "nixosAppHelpers not available - ensure meta/nixos-app-helpers.nix is imported");
  inherit (helpers) getApps;

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
    # "ventoy-full" # Marked as insecure - enable manually if needed
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
    "veracrypt"
  ];
in
{
  configurations.nixos.system76.module.imports = getApps fileAppNames;
}
