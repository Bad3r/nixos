/*
  Package: gparted
  Description: GNOME Partition Editor for resizing, copying, and managing disk partitions graphically.
  Homepage: https://gparted.org/
  Documentation: https://gparted.org/display-doc.php
  Repository: https://gitlab.gnome.org/GNOME/gparted

  Summary:
    * Provides a GUI for manipulating partition tables, creating filesystems, aligning partitions, and inspecting device details.
    * Supports FAT, NTFS, ext*, Btrfs, LVM2 PVs, and more, with operations queued for preview before committing changes.
*/
_:
let
  GpartedModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.gparted.extended;
    in
    {
      options.programs.gparted.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable gparted.";
        };

        package = lib.mkPackageOption pkgs "gparted" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.gparted = GpartedModule;
}
