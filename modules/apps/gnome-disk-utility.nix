/*
  Package: gnome-disk-utility
  Description: GNOME Disks GUI for managing storage devices, partitions, and SMART data.
  Homepage: https://apps.gnome.org/app/org.gnome.DiskUtility/
  Documentation: https://help.gnome.org/users/gnome-disks/stable/
  Repository: https://gitlab.gnome.org/GNOME/gnome-disk-utility

  Summary:
    * Provides a graphical interface for formatting drives, resizing partitions, creating disk images, and benchmarking storage.
    * Integrates SMART diagnostics, encryption setup (LUKS), and mount option editing for both local and removable devices.
*/
_:
let
  GnomeDiskUtilityModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."gnome-disk-utility".extended;
    in
    {
      options.programs.gnome-disk-utility.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable gnome-disk-utility.";
        };

        package = lib.mkPackageOption pkgs "gnome-disk-utility" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.gnome-disk-utility = GnomeDiskUtilityModule;
}
