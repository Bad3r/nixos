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

  Example Usage:
    * `sedutil-cli --scan` -- Discover which attached drives report Opal support.
    * `sedutil-cli --query /dev/nvme0n1` -- Read the Discovery 0 response of an NVMe drive.
    * `sedutil-cli --printDefaultPassword /dev/sda` -- Read the factory MSID before taking ownership.

  Notes:
    * `disk` group members run `sedutil-cli` without `sudo` through a capability wrapper carrying CAP_SYS_ADMIN and CAP_SYS_RAWIO.
    * SATA drives also need `libata.allow_tpm=1` (docs/sedutil-cli.8), set in `modules/hosts/common/storage-diagnostics.nix` and applied on the next reboot. NVMe drives are unaffected.
    * The wrapper covers the whole binary, so the password and revert subcommands (`--initialSetup`, `--revertTPer`, `--yesIreallywanttoERASEALLmydatausingthePSID`) also lose the sudo prompt, and the last two destroy data.
    * `linuxpba` ships in the same package and stays unwrapped, so it still needs `sudo`.
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

      # `Common/system.cpp` links a popen() helper into sedutil-cli, and popen
      # execs `/bin/sh -c`, which resolves command names from PATH. PATH is not
      # in glibc's unsecvars list, so the capability wrapper forwards the
      # caller's value and the ambient caps would survive into whatever the
      # shell found. Pinning PATH here removes that lookup from caller control.
      pinnedPath =
        pkgs.runCommand "sedutil-cli-pinned-path"
          {
            nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
          }
          ''
            makeWrapper ${cfg.package}/bin/sedutil-cli "$out/bin/sedutil-cli" \
              --set PATH ${lib.makeBinPath [ pkgs.coreutils ]}
          '';
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

        # Opal traffic leaves through two gated ioctls: blk_verify_command()
        # rejects the SECURITY PROTOCOL IN/OUT and ATA PASS-THROUGH CDBs that
        # SG_IO carries without CAP_SYS_RAWIO, and nvme_cmd_allowed() rejects
        # the NVMe security send/receive admin passthrough without
        # CAP_SYS_ADMIN.
        security.wrappers.sedutil-cli = {
          source = "${pinnedPath}/bin/sedutil-cli";
          capabilities = "cap_sys_admin,cap_sys_rawio+ep";
          owner = "root";
          group = "disk";
          permissions = "u+rx,g+x";
        };
      };
    };
in
{
  flake.nixosModules.apps.sedutil = SedutilModule;
}
