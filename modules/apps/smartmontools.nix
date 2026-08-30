/*
  Package: smartmontools
  Description: Tools for monitoring and controlling storage devices via SMART (Self-Monitoring, Analysis and Reporting Technology).
  Homepage: https://www.smartmontools.org/
  Documentation: https://www.smartmontools.org/wiki/Documentation
  Repository: https://github.com/smartmontools/smartmontools

  Summary:
    * Provides `smartctl` for querying disk health, running self-tests, and enabling SMART features, plus the `smartd` daemon for scheduled monitoring and alerts.
    * Supports SATA, NVMe, SCSI, and USB-enclosed devices with extensive reporting of attributes and error logs.

  Options:
    smartctl -a /dev/sdX: Display all SMART information for a drive.
    smartctl -t short /dev/sdX: Start a short self-test.
    smartctl -H /dev/nvme0: Report overall health status.
    smartd.conf: Configure daemon monitoring intervals and notification methods.

  Example Usage:
    * `smartctl -a /dev/sda` -- Review detailed health metrics and error logs.
    * `smartctl -a /dev/nvme0n1` -- Read the NVMe SMART/health, error and self-test logs.
    * `smartctl -t long /dev/sda` -- Initiate an extended self-test (run in background).
    * Edit `/etc/smartd.conf` to schedule weekly tests and email alerts via `smartd`.

  Notes:
    * `disk` group members run the audited `smartctl` reports and standard self-tests without `sudo` through a compiled argv filter and a capability wrapper carrying CAP_SYS_ADMIN and CAP_SYS_RAWIO.
    * The filter retains capabilities for reports, settings reads including `-n sleep|standby|idle[,STATUS[,STATUS2]]`, and `offline`, `short`, `long`, and `conveyance` self-tests. Configuration, reset, vendor, selective, pending, force, captive, abort, and unknown forms clear the ambient set and need `sudo` again.
*/
_:
let
  SmartmontoolsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.smartmontools.extended;
    in
    {
      options.programs.smartmontools.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable smartmontools.";
        };

        package = lib.mkPackageOption pkgs "smartmontools" { };
      };

      config = lib.mkIf cfg.enable (
        let
          # smartctl combines read-only reports with device-mutating options. Its
          # getopt_long parser permutes options around operands, so the compiled
          # filter scans the complete argv and keeps capabilities only for the
          # audited reports and standard tests documented above. Unsupported,
          # state-changing, and future options take the cleared-capability path.
          argvFilter = pkgs.writeCBin "smartctl-argv-filter" ''
            #include <ctype.h>
            #include <stdio.h>
            #include <string.h>
            #include <sys/prctl.h>
            #include <unistd.h>

            static char real_prog[] = "${cfg.package}/bin/smartctl";

            enum {
              opt_identify = 1000,
              opt_json,
              opt_scan,
              opt_scan_open
            };

            static const char *const quiet_values[] = {
              "errorsonly",
              "silent",
              "noserial",
              NULL
            };

            static const char *const tolerance_values[] = {
              "normal",
              "conservative",
              "permissive",
              "verypermissive",
              NULL
            };

            static const char *const badsum_values[] = {
              "warn",
              "exit",
              "ignore",
              NULL
            };

            static const char *const preset_values[] = {
              "use",
              "ignore",
              "show",
              "showall",
              NULL
            };

            static const char *const format_values[] = {
              "old",
              "brief",
              "hex",
              "hex,id",
              "hex,val",
              NULL
            };

            static int is_one_of(const char *value, const char *const *allowed)
            {
              int i;

              for (i = 0; allowed[i] != NULL; i++) {
                if (strcmp(value, allowed[i]) == 0)
                  return 1;
              }
              return 0;
            }

            static int is_decimal_range(const char *start, const char *end,
                                        unsigned max, int nonzero)
            {
              unsigned number = 0;
              const unsigned char *p = (const unsigned char *) start;

              if (start == end)
                return 0;
              for (; p < (const unsigned char *) end; p++) {
                if (!isdigit(*p))
                  return 0;
                if (number > (max - (*p - '0')) / 10)
                  return 0;
                number = number * 10 + (*p - '0');
              }
              return !nonzero || number != 0;
            }

            static int is_decimal(const char *value, unsigned max, int nonzero)
            {
              return is_decimal_range(value, value + strlen(value), max, nonzero);
            }

            static int is_hex_byte(const char *value)
            {
              const unsigned char *p = (const unsigned char *) value;
              int digits = 0;

              if (p[0] != '0' || p[1] != 'x')
                return 0;
              for (p += 2; *p != '\0'; p++) {
                if (!isxdigit(*p) || ++digits > 2)
                  return 0;
              }
              return digits > 0;
            }

            static int is_device_type(const char *value)
            {
              const unsigned char *p = (const unsigned char *) value;

              if (*p == '\0' || *p == '-')
                return 0;
              for (; *p != '\0'; p++) {
                if (isalnum(*p) || strchr("-_.+,/:", *p) != NULL)
                  continue;
                return 0;
              }
              return 1;
            }

            static int is_report(const char *value)
            {
              const char *comma = strchr(value, ',');
              size_t length = comma == NULL ? strlen(value) : (size_t) (comma - value);

              if (!((length == strlen("ioctl") && strncmp(value, "ioctl", length) == 0) ||
                    (length == strlen("ataioctl") && strncmp(value, "ataioctl", length) == 0) ||
                    (length == strlen("scsiioctl") && strncmp(value, "scsiioctl", length) == 0) ||
                    (length == strlen("nvmeioctl") && strncmp(value, "nvmeioctl", length) == 0)))
                return 0;
              return comma == NULL ||
                (comma[1] >= '1' && comma[1] <= '4' && comma[2] == '\0');
            }

            static int is_nocheck(const char *value)
            {
              const char *comma = strchr(value, ',');

              if (strcmp(value, "never") == 0)
                return 1;
              /* smartctl makes the status components optional for these modes. */
              if (comma == NULL)
                return strcmp(value, "sleep") == 0 ||
                  strcmp(value, "standby") == 0 ||
                  strcmp(value, "idle") == 0;
              if (!((strncmp(value, "sleep", (size_t) (comma - value)) == 0 && comma - value == 5) ||
                    (strncmp(value, "standby", (size_t) (comma - value)) == 0 && comma - value == 7) ||
                    (strncmp(value, "idle", (size_t) (comma - value)) == 0 && comma - value == 4)))
                return 0;

              {
                const char *first = comma + 1;
                const char *second = strchr(first, ',');

                if (second == NULL)
                  return is_decimal(first, 255, 0);
                if (!is_decimal_range(first, second, 255, 0))
                  return 0;
                return is_decimal(second + 1, 255, 0);
              }
            }

            static int is_log(const char *value)
            {
              const char *comma;

              if (is_one_of(value, (const char *const[]) {
                    "selftest", "selective", "directory", "directory,g", "directory,s",
                    "background", "sasphy", "sataphy", "genstats", "scterc", "scterc,p",
                    "scttemp", "scttempsts", "scttemphist", "ssd", "envrep", "farm",
                    "tapealert", "tapedevstat", "zdevstat", NULL
                  }))
                return 1;

              if (strcmp(value, "error") == 0)
                return 1;
              if (strncmp(value, "error,", strlen("error,")) == 0)
                return is_decimal(value + strlen("error,"), 0xffffffffU, 1);

              if (strcmp(value, "xerror") == 0 || strcmp(value, "xerror,error") == 0 ||
                  strcmp(value, "xselftest") == 0 || strcmp(value, "xselftest,selftest") == 0)
                return 1;
              if (strncmp(value, "xerror,", strlen("xerror,")) == 0) {
                const char *number = value + strlen("xerror,");

                comma = strchr(number, ',');
                if (comma == NULL)
                  return is_decimal(number, 0xffffffffU, 1);
                return is_decimal_range(number, comma, 0xffffffffU, 1) &&
                  strcmp(comma, ",error") == 0;
              }
              if (strncmp(value, "xselftest,", strlen("xselftest,")) == 0) {
                const char *number = value + strlen("xselftest,");

                comma = strchr(number, ',');
                if (comma == NULL)
                  return is_decimal(number, 0xffffffffU, 1);
                return is_decimal_range(number, comma, 0xffffffffU, 1) &&
                  strcmp(comma, ",selftest") == 0;
              }
              if (strncmp(value, "devstat,", strlen("devstat,")) == 0)
                return is_decimal(value + strlen("devstat,"), 255, 0) ||
                  is_hex_byte(value + strlen("devstat,"));
              if (strncmp(value, "defects,", strlen("defects,")) == 0)
                return is_decimal(value + strlen("defects,"), 2097119, 0);
              if (strcmp(value, "devstat") == 0 || strcmp(value, "defects") == 0)
                return 1;
              return 0;
            }

            static int is_safe_value(int option, const char *value)
            {
              switch (option) {
              case 'q': return is_one_of(value, quiet_values);
              case 'd': return is_device_type(value);
              case 'T': return is_one_of(value, tolerance_values);
              case 'b': return is_one_of(value, badsum_values);
              case 'r': return is_report(value);
              case 'l': return is_log(value);
              case 'n': return is_nocheck(value);
              case 'f': return is_one_of(value, format_values);
              case 'g': return is_one_of(value, (const char *const[]) {
                "all", "aam", "apm", "dsn", "lookahead", "security", "wcache", "rcache",
                "wcreorder", "wcache-sct", NULL
              });
              case 'P': return is_one_of(value, preset_values);
              case 't': return is_one_of(value, (const char *const[]) {
                "offline", "short", "long", "conveyance", NULL
              });
              case opt_json:
                return *value != '\0' && strspn(value, "cgiosuvy") == strlen(value);
              case opt_identify:
                return *value != '\0' && strspn(value, "wnvb") == strlen(value);
              default:
                return 0;
              }
            }

            static int is_short_noarg(int option)
            {
              return strchr("h?ViHcAaxj", option) != NULL;
            }

            static int is_short_arg(int option)
            {
              return strchr("dTbrqnlfgPt", option) != NULL;
            }

            static int has_name(const char *name, size_t length, const char *expected)
            {
              return length == strlen(expected) && strncmp(name, expected, length) == 0;
            }

            static int long_option(const char *name, size_t length)
            {
              if (has_name(name, length, "help") || has_name(name, length, "usage")) return 'h';
              if (has_name(name, length, "version") || has_name(name, length, "copyright") ||
                  has_name(name, length, "license")) return 'V';
              if (has_name(name, length, "info")) return 'i';
              if (has_name(name, length, "get")) return 'g';
              if (has_name(name, length, "all")) return 'a';
              if (has_name(name, length, "xall")) return 'x';
              if (has_name(name, length, "scan")) return opt_scan;
              if (has_name(name, length, "scan-open")) return opt_scan_open;
              if (has_name(name, length, "json")) return opt_json;
              if (has_name(name, length, "identify")) return opt_identify;
              if (has_name(name, length, "quietmode")) return 'q';
              if (has_name(name, length, "device")) return 'd';
              if (has_name(name, length, "tolerance")) return 'T';
              if (has_name(name, length, "badsum")) return 'b';
              if (has_name(name, length, "report")) return 'r';
              if (has_name(name, length, "health")) return 'H';
              if (has_name(name, length, "capabilities")) return 'c';
              if (has_name(name, length, "attributes")) return 'A';
              if (has_name(name, length, "log")) return 'l';
              if (has_name(name, length, "nocheck")) return 'n';
              if (has_name(name, length, "format")) return 'f';
              if (has_name(name, length, "presets")) return 'P';
              if (has_name(name, length, "test")) return 't';
              return 0;
            }

            static int parse_short(int argc, char **argv, int *index, const char *arg)
            {
              const char *option = arg + 1;

              while (*option != '\0') {
                if (is_short_noarg((unsigned char) *option)) {
                  option++;
                  continue;
                }
                if (!is_short_arg((unsigned char) *option))
                  return 0;

                if (option[1] == '\0') {
                  if (++*index >= argc || argv[*index] == NULL)
                    return 0;
                  return is_safe_value((unsigned char) *option, argv[*index]);
                }
                return is_safe_value((unsigned char) *option, option + 1);
              }
              return 1;
            }

            static int parse_long(int argc, char **argv, int *index, const char *arg)
            {
              const char *name = arg + 2;
              const char *equals = strchr(name, '=');
              size_t length = equals == NULL ? strlen(name) : (size_t) (equals - name);
              int option = long_option(name, length);
              const char *value;

              if (option == 0)
                return 0;
              if (option == opt_scan || option == opt_scan_open || is_short_noarg(option))
                return equals == NULL;
              if (option == opt_json || option == opt_identify) {
                return equals == NULL || is_safe_value(option, equals + 1);
              }
              if (!is_short_arg(option))
                return 0;
              if (equals == NULL) {
                if (++*index >= argc || argv[*index] == NULL)
                  return 0;
                value = argv[*index];
              } else {
                value = equals + 1;
              }
              return is_safe_value(option, value);
            }

            static int keeps_capability(int argc, char **argv)
            {
              int found = 0;
              int operands = 0;
              int i;

              for (i = 1; i < argc; i++) {
                const char *arg = argv[i];

                if (arg == NULL)
                  return 0;
                if (arg[0] != '-' || arg[1] == '\0') {
                  if (++operands > 1)
                    return 0;
                  continue;
                }
                if (arg[1] == '-') {
                  int j;

                  if (arg[2] == '\0') {
                    for (j = i + 1; j < argc; j++) {
                      if (++operands > 1)
                        return 0;
                    }
                    break;
                  }
                  if (!parse_long(argc, argv, &i, arg))
                    return 0;
                } else if (!parse_short(argc, argv, &i, arg)) {
                  return 0;
                }
                found = 1;
              }
              return found;
            }

            int main(int argc, char **argv)
            {
              if (!keeps_capability(argc, argv) &&
                  prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_CLEAR_ALL, 0, 0, 0) != 0) {
                perror("smartctl: PR_CAP_AMBIENT_CLEAR_ALL");
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
          environment.systemPackages = [ cfg.package ];

          # Two separate kernel gates sit in front of SMART data: NVMe admin
          # passthrough checks CAP_SYS_ADMIN, and the SG_IO command filter that
          # ATA-over-SAT reads go through checks CAP_SYS_RAWIO.
          security.wrappers.smartctl = {
            source = "${argvFilter}/bin/smartctl-argv-filter";
            capabilities = "cap_sys_admin,cap_sys_rawio+ep";
            owner = "root";
            group = "disk";
            permissions = "u+rx,g+x";
          };
        }
      );
    };
in
{
  flake.nixosModules.apps.smartmontools = SmartmontoolsModule;
}
