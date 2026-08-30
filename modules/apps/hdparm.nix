/*
  Package: hdparm
  Description: Linux utility for querying and setting ATA/SATA drive parameters.
  Homepage: https://sourceforge.net/projects/hdparm/
  Documentation: https://linux.die.net/man/8/hdparm
  Repository: https://github.com/stormogulen/hdparm (mirror)

  Summary:
    * Retrieves disk information (geometry, SMART-like stats) and controls power management, caching, and acoustic parameters.
    * Useful for benchmarking (`-tT`), setting spin-down timers, and enabling features like write caching or DMA.

  Options:
    -I <device>: Display detailed drive identification, including firmware and feature support.
    -tT <device>: Perform cached and buffered read timing tests.
    -S <value>: Configure standby (spin-down) timeout.
    -B <value>: Set Advanced Power Management level (0-255).
    -y/-Y/-Z <device>: Put the drive into standby, sleep, or sleep mode (requires caution).

  Example Usage:
    * `hdparm -I /dev/sda` -- Inspect drive capabilities and feature set.
    * `hdparm -tT /dev/nvme0n1` -- Benchmark sequential read performance for an NVMe device.
    * `sudo hdparm -S 120 /dev/sdb` -- Spin down a drive after 10 minutes of inactivity (120 x 5 seconds).

  Notes:
    * `disk` group members run non-media-mutating diagnostics without `sudo` through a capability wrapper carrying CAP_SYS_ADMIN and CAP_SYS_RAWIO.
    * The compiled argv filter keeps capabilities only for short-option clusters made from `-C`, `-g`, `-i`, `-I`, `-t`, and `-T`. Standalone input formatting such as `--Istdin`, state-changing, parameter-bearing, and unknown options clear the ambient set and need `sudo` again.
*/
_:
let
  HdparmModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.hdparm.extended;

      # hdparm parses short-option clusters itself rather than using getopt,
      # so inspect every argv element. Keep capabilities only for flags that
      # query device state or run timings; standalone input formatting, all
      # get/set, and unknown options take the cleared-capability path.
      argvFilter = pkgs.writeCBin "hdparm-argv-filter" ''
        #include <stdio.h>
        #include <string.h>
        #include <sys/prctl.h>
        #include <unistd.h>

        static char real_prog[] = "${cfg.package}/bin/hdparm";

        static int is_read_only_short_cluster(const char *arg)
        {
          const char *flag;

          if (arg[0] != '-' || arg[1] == '\0' || arg[1] == '-')
            return 0;

          for (flag = arg + 1; *flag != '\0'; flag++) {
            if (strchr("CgiItT", *flag) == NULL)
              return 0;
          }
          return 1;
        }

        static int keeps_capability(int argc, char **argv)
        {
          int found = 0;
          int i;

          if (argc < 2 || argv[1] == NULL)
            return 0;

          for (i = 1; i < argc; i++) {
            const char *arg = argv[i];

            if (arg == NULL)
              return 0;
            if (arg[0] != '-' || arg[1] == '\0')
              continue;
            if (strcmp(arg, "--") == 0)
              break;
            if (arg[1] == '-')
              return 0;
            if (!is_read_only_short_cluster(arg))
              return 0;
            found = 1;
          }
          return found;
        }

        int main(int argc, char **argv)
        {
          if (!keeps_capability(argc, argv) &&
              prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_CLEAR_ALL, 0, 0, 0) != 0) {
            perror("hdparm: PR_CAP_AMBIENT_CLEAR_ALL");
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
      options.programs.hdparm.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable hdparm.";
        };

        package = lib.mkPackageOption pkgs "hdparm" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        # ata_sas_scsi_ioctl() requires CAP_SYS_ADMIN and CAP_SYS_RAWIO together
        # for HDIO_DRIVE_CMD / HDIO_DRIVE_TASK, so -I and the other identify
        # paths return EACCES for a plain `disk` member. The filter clears these
        # capabilities before state-changing or unknown options run.
        security.wrappers.hdparm = {
          source = "${argvFilter}/bin/hdparm-argv-filter";
          capabilities = "cap_sys_admin,cap_sys_rawio+ep";
          owner = "root";
          group = "disk";
          permissions = "u+rx,g+x";
        };
      };
    };
in
{
  flake.nixosModules.apps.hdparm = HdparmModule;
}
