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
  flake.nixosModules.apps."util-linux" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."util-linux" ];
    };
}
