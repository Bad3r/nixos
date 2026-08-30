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
    * `disk` group members run selected `sedutil-cli` diagnostics without `sudo` through a compiled argv filter and a capability wrapper carrying CAP_SYS_ADMIN and CAP_SYS_RAWIO.
    * SATA drives also need `libata.allow_tpm=1` (docs/sedutil-cli.8), set in `modules/hosts/common/storage-diagnostics.nix` while sedutil is enabled and applied on the next reboot. NVMe drives are unaffected.
    * For the sedutil 1.49.13 parser, the filter keeps capabilities only for `--scan` (with its JSON output forms), `--query` (with its JSON output forms and one device), `--isValidSED <device>`, and `--printDefaultPassword <device>`. State-changing actions clear the ambient set and need `sudo` again; `--revertTPer` and `--yesIreallywanttoERASEALLmydatausingthePSID` destroy data. A custom package must be re-audited if its argument parser changes.
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
      # caller's value. The argv filter clears ambient capabilities for every
      # action that could reach the helper, while this fixed PATH remains a
      # defense-in-depth boundary for the helper lookup.
      pinnedPath =
        pkgs.runCommand "sedutil-cli-pinned-path"
          {
            nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
          }
          ''
            makeWrapper ${cfg.package}/bin/sedutil-cli "$out/bin/sedutil-cli" \
              --set PATH ${lib.makeBinPath [ pkgs.coreutils ]}
          '';

      # Keep capabilities only for read actions in the sedutil 1.49.13 parser.
      # Its exact and maximum argument checks reject later actions before
      # dispatch; unsupported first actions clear the ambient set. Re-audit a
      # custom package if its argument parser changes.
      argvFilter = pkgs.writeCBin "sedutil-cli-argv-filter" ''
        #include <stdio.h>
        #include <string.h>
        #include <sys/prctl.h>
        #include <unistd.h>

        static char real_prog[] = "${pinnedPath}/bin/sedutil-cli";

        static const char *const allowed[] = {
          "--scan",
          "--query",
          "--isValidSED",
          "--printDefaultPassword",
          NULL
        };

        static int keeps_capability(int argc, char **argv)
        {
          int i;

          if (argc < 2 || argv[1] == NULL)
            return 0;

          for (i = 0; allowed[i] != NULL; i++) {
            if (strcmp(argv[1], allowed[i]) == 0)
              return 1;
          }
          return 0;
        }

        int main(int argc, char **argv)
        {
          if (!keeps_capability(argc, argv) &&
              prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_CLEAR_ALL, 0, 0, 0) != 0) {
            perror("sedutil-cli: PR_CAP_AMBIENT_CLEAR_ALL");
            return 126;
          }

          if (argc > 0)
            argv[0] = real_prog;
          execv(real_prog, argv);
          perror(real_prog);
          return 127;
        }
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
          source = "${argvFilter}/bin/sedutil-cli-argv-filter";
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
