/*
  Package: util-linux
  Description: Collection of essential low-level Linux system administration utilities.
  Homepage: https://github.com/util-linux/util-linux
  Documentation: https://man7.org/linux/man-pages/man8/util-linux.8.html
  Repository: https://github.com/util-linux/util-linux

  Summary:
    * Provides tools such as `mount`, `lsblk`, `fdisk`, `login`, and `setarch` for managing Linux systems.
    * Maintains actively developed replacements for legacy utilities with modern filesystem and namespace support.

  Options:
    -f: Display filesystem information in `lsblk -f` output.
    -l: Enumerate partition tables across disks when running `fdisk -l`.
    --bind <src> <dest>: Bind-mount a directory using the util-linux `mount` implementation.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.util-linux.extended;
  UtilLinuxModule = {
    options.programs.util-linux.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable util-linux.";
      };

      package = lib.mkPackageOption pkgs "util-linux" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.util-linux = UtilLinuxModule;
}
