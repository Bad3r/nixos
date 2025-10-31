/*
  Package: gptfdisk
  Description: Set of text-mode partitioning tools for GUID Partition Table (GPT) disks.
  Homepage: https://www.rodsbooks.com/gdisk/
  Documentation: https://www.rodsbooks.com/gdisk/sgdisk.html
  Repository: https://sourceforge.net/p/gptfdisk/code/ci/master/tree/

  Summary:
    * Ships `gdisk`, `cgdisk`, `sgdisk`, and `fixparts` utilities for creating, inspecting, and repairing GPT partition tables.
    * Helps migrate from MBR, back up partition tables, and script provisioning flows across Linux and other UNIX-like systems.

  Options:
    --print <disk>: Display the GPT partition table in a non-interactive script-friendly format (`sgdisk --print`).
    --backup=<file>: Write the primary and backup GPT headers to a binary backup file (`sgdisk --backup`).
    --load-backup=<file>: Restore a saved GPT backup onto the target disk (`sgdisk --load-backup`).
    --zap-all: Erase both GPT and MBR data structures from a disk before repartitioning.

  Example Usage:
    * `gdisk /dev/nvme0n1` — Interactively review and edit partitions on an NVMe disk.
    * `sgdisk --print /dev/sda` — List partition layout for scripts or troubleshooting.
    * `sgdisk --backup=~/backups/sda.gpt --print /dev/sda` — Save a GPT backup before modifying the table.
*/

{
  flake.homeManagerModules.apps.gptfdisk =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.gptfdisk.extended;
    in
    {
      options.programs.gptfdisk.extended = {
        enable = lib.mkEnableOption "Set of text-mode partitioning tools for GUID Partition Table (GPT) disks.";
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.gptfdisk ];
      };
    };
}
