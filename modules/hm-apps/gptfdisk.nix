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
    gdisk /dev/<disk>: Launch the interactive GPT partition editor for a specific disk.
    sgdisk --print <disk>: Display the GPT partition table in a non-interactive script-friendly format.
    sgdisk --backup=<file>: Write the primary and backup GPT headers to a binary backup file.
    sgdisk --load-backup=<file>: Restore a saved GPT backup onto the target disk.
    fixparts /dev/<disk>: Convert or repair MBR partition tables when transitioning to GPT.

  Example Usage:
    * `gdisk /dev/nvme0n1` — Interactively review and edit partitions on an NVMe disk.
    * `sgdisk --print /dev/sda` — List partition layout for scripts or troubleshooting.
    * `sgdisk --backup=~/backups/sda.gpt --print /dev/sda` — Save a GPT backup before modifying the table.
*/

{
  flake.homeManagerModules.apps.gptfdisk =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.gptfdisk ];
    };
}
