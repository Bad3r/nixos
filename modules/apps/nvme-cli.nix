/*
  Package: nvme-cli
  Description: Command-line interface for managing NVMe SSD devices on Linux.
  Homepage: https://github.com/linux-nvme/nvme-cli
  Documentation: https://docs.kernel.org/admin-guide/nvme.html
  Repository: https://github.com/linux-nvme/nvme-cli

  Summary:
    * Provides tools to query NVMe controller information, SMART data, namespaces, and perform firmware updates or format commands.
    * Supports monitoring health, running self-tests, and interacting with NVMe over Fabrics targets.

  Options:
    nvme list: Enumerate detected NVMe devices and namespaces.
    nvme smart-log /dev/nvme0: Display SMART/health info for a drive.
    nvme format /dev/nvme0n1 --force: Format a namespace (destructive, use with caution).
    nvme fw-log /dev/nvme0: Inspect firmware slots.
    nvme device-self-test /dev/nvme0 --start short: Run a short self-test.

  Example Usage:
    * `nvme list` -- Discover NVMe devices attached to the system.
    * `nvme smart-log /dev/nvme0` -- Check drive temperature, media errors, and wear indicators.
    * `nvme device-self-test /dev/nvme0 --start extended` -- Initiate an extended diagnostic self-test.

  Notes:
    * `disk` group members run this without `sudo`: a capability wrapper supplies CAP_SYS_ADMIN and the shared storage policy opens the controller char nodes.
    * The wrapper source is an argv filter that only keeps the capability for an allowlist of read-only diagnostic subcommands plus `device-self-test`, whose options can start or abort a drive self-test. Every other subcommand still runs, with the ambient set cleared, so `format`, `sanitize`, `set-feature`, `fw-commit` and the vendor plugins need `sudo` again.
    * `nvme help <cmd>` and the vendor plugins are in the cleared path: plugin.c:52 `execlp`s `man`, and the plugins interpolate `--dir-name` into a `system()` string (solidigm-internal-logs.c:989, wdc-nvme.c:4218).
*/
_:
let
  NvmeCliModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."nvme-cli".extended;

      # security.wrappers raises cap_sys_admin into the ambient set
      # (wrapper.c:137), which survives execve into a file without capabilities,
      # so it would reach anything nvme runs. The vendor plugins interpolate the
      # caller's --dir-name into a shell string (solidigm-internal-logs.c:989,
      # wdc-nvme.c:4218, micron-nvme.c:249), which no PATH can bound, so the
      # filter drops the ambient set instead. It has to be a compiled binary:
      # cap wrappers are not setuid, so euid == uid, bash never enters
      # privileged mode, and BASH_ENV is absent from glibc's unsecvars.h.
      argvFilter = pkgs.writeCBin "nvme-argv-filter" ''
        #include <stdio.h>
        #include <string.h>
        #include <sys/prctl.h>
        #include <unistd.h>

        static char real_prog[] = "${cfg.package}/bin/nvme";

        /* nvme.c:11153 dispatches argv[1]. Each name is an exact nvme-builtin.h
           entry, so handle_plugin's strcmp arm (plugin.c:186) wins before its
           unique-prefix and plugin-extension arms, and nvme.c holds no
           system()/popen()/exec* call for any of them to reach. */
        static const char *const allowed[] = {
        	"ana-log",
        	"ave-discovery-log",
        	"boot-part-log",
        	"device-self-test",
        	"dispersed-ns-participating-nss-log",
        	"effects-log",
        	"endurance-event-agg-log",
        	"endurance-log",
        	"error-log",
        	"fid-support-effects-log",
        	"fw-log",
        	"get-feature",
        	"get-log",
        	"host-discovery-log",
        	"id-ctrl",
        	"id-domain",
        	"id-iocs",
        	"id-ns",
        	"id-ns-granularity",
        	"id-ns-lba-format",
        	"id-nvmset",
        	"id-uuid",
        	"lba-status-log",
        	"list",
        	"list-ctrl",
        	"list-endgrp",
        	"list-ns",
        	"list-secondary",
        	"list-subsys",
        	"media-unit-stat-log",
        	"mgmt-addr-list-log",
        	"mi-cmd-support-effects-log",
        	"ns-descs",
        	"nvm-id-ns-lba-format",
        	"pred-lat-event-agg-log",
        	"predictable-lat-log",
        	"primary-ctrl-caps",
        	"pull-model-ddc-req-log",
        	"reachability-associations-log",
        	"reachability-groups-log",
        	"resv-notif-log",
        	"rotational-media-info-log",
        	"sanitize-log",
        	"self-test-log",
        	"smart-log",
        	"supported-cap-config-log",
        	"supported-log-pages",
        	"telemetry-log",
        	NULL
        };

        int main(int argc, char **argv)
        {
        	int keep = 0;
        	int i;

        	/* Compared verbatim. plugin.c:174 strips leading dashes before
        	   dispatch, so `--smart-log` reaches the same builtin but takes the
        	   cleared path. */
        	for (i = 0; argc > 1 && allowed[i] != NULL; i++) {
        		if (strcmp(argv[1], allowed[i]) == 0) {
        			keep = 1;
        			break;
        		}
        	}

        	/* An execve after this gets new_permitted = file_caps(0) | ambient(0). */
        	if (!keep && prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_CLEAR_ALL, 0, 0, 0) != 0) {
        		perror("nvme: PR_CAP_AMBIENT_CLEAR_ALL");
        		return 126;
        	}

        	/* execve(2) permits argc == 0, where argv[0] is the NULL terminator. */
        	if (argc > 0)
        		argv[0] = real_prog;
        	execv(real_prog, argv);
        	perror(real_prog);
        	return 127;
        }
      '';
    in
    {
      options.programs.nvme-cli.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nvme-cli.";
        };

        package = lib.mkPackageOption pkgs "nvme-cli" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        # nvme_cmd_allowed() rejects every admin passthrough except a few
        # identify CNS values without CAP_SYS_ADMIN, so smart-log, error-log,
        # fw-log and telemetry fail with EACCES for a plain `disk` member.
        security.wrappers.nvme = {
          source = "${argvFilter}/bin/nvme-argv-filter";
          capabilities = "cap_sys_admin+ep";
          owner = "root";
          group = "disk";
          permissions = "u+rx,g+x";
        };
      };
    };
in
{
  flake.nixosModules.apps.nvme-cli = NvmeCliModule;
}
