/*
  Package: gnome-disk-utility
  Description: GNOME Disks GUI for managing storage devices, partitions, and SMART data.
  Homepage: https://apps.gnome.org/app/org.gnome.DiskUtility/
  Documentation: https://help.gnome.org/users/gnome-disks/stable/
  Repository: https://gitlab.gnome.org/GNOME/gnome-disk-utility

  Summary:
    * Provides a graphical interface for formatting drives, resizing partitions, creating disk images, and benchmarking storage.
    * Integrates SMART diagnostics, encryption setup (LUKS), and mount option editing for both local and removable devices.

  Options:
    gnome-disks: Launch the GNOME Disks application.
    --gsettings: Respect GNOME settings for auto-mount and power management.
    (Most operations are performed interactively through the GUI menus.)

  Example Usage:
    * `gnome-disks` — Open the GNOME Disks application to inspect devices, run benchmarks, or configure mounts.
    * Use the “Create Disk Image…” menu to back up a removable drive to an image file.
    * Use “SMART Data & Self-Tests” to review drive health and initiate a self-test.
*/

{
  flake.nixosModules.apps."gnome-disk-utility" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gnome-disk-utility ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gnome-disk-utility ];
    };
}
