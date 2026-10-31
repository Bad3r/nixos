/*
  Package: sedutil
  Description: Command-line manager for TCG Opal 2.0 self-encrypting drives.
  Homepage: https://www.drivetrust.com
  Documentation: https://github.com/Drive-Trust-Alliance/sedutil/wiki
  Repository: https://github.com/Drive-Trust-Alliance/sedutil

  Summary:
    * Takes ownership of an Opal drive, manages locking ranges, MBR shadowing, and pre-boot authentication images.
    * Reaches SATA drives through SCSI/ATA translation and NVMe drives through admin security send/receive.

  Options:
    --scan: List devices and mark the Opal compliant ones.
    --query <device>: Print the Discovery 0 feature descriptors of a device.
    --isValidSED <device>: Report whether a device is a self-encrypting drive.
    --initialSetup <SIDpassword> <device>: Take ownership and set the SID and Admin1 passwords.
    --setLockingRange <0...n> <RW|RO|LK> <Admin1password> <device>: Change the state of a locking range.
    --loadPBAimage <Admin1password> <file> <device>: Write a pre-boot authentication image to the MBR shadow area.
    --revertTPer <SIDpassword> <device>: Restore factory defaults, erasing all data.
    --printDefaultPassword <device>: Print the drive MSID.

  Notes:
    * Device actions need `sudo`.
    * SATA drives need `libata.allow_tpm=1`, set automatically and applied on the next reboot.
    * The drive MSID is credential material.
*/
_:
let
  SedutilModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.sedutil.extended;
    in
    {
      options.programs.sedutil.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable sedutil.";
        };

        package = lib.mkPackageOption pkgs "sedutil" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.sedutil = SedutilModule;
}
