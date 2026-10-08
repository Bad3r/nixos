/*
  Package: nethogs
  Description: Small "net top" tool that groups bandwidth by process.
  Homepage: https://github.com/raboof/nethogs
  Documentation: https://github.com/raboof/nethogs#readme
  Repository: https://github.com/raboof/nethogs

  Summary:
    * Sniffs network devices and sums sent and received traffic per process instead of per protocol or subnet.
    * Offers an interactive ncurses view and a plain-text trace mode for scripting.

  Options:
    -d <seconds>: Refresh delay (default 1).
    -v <mode>: View mode: 0 kB/s, 1 total kB, 2 total bytes, 3 total MB, 4 MB/s, 5 GB/s.
    -t: Trace mode, printing plain-text updates instead of the TUI.
    -C: Capture UDP as well as TCP.
    -a: Monitor all devices, including loopback and stopped ones.
    -P <pid>: Show only the given process ID; repeat for more.

  Notes:
    * Installs a capability wrapper so `wheel` users can run nethogs without invoking `sudo`; `cap_sys_ptrace` and `cap_dac_read_search` let it read every process's `/proc/<pid>/fd` to attribute sockets to processes.
    * The wrapper source passes only `TERM` and `TERMINFO_DIRS=/run/current-system/sw/share/terminfo` to nethogs, so caller-set `TERMINFO`, `TERMINFO_DIRS`, and `~/.terminfo` entries are ignored.
*/
_:
let
  NethogsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.nethogs.extended;

      # Ambient caps leave AT_SECURE at 0, so ncurses' _nc_env_access() would
      # honor caller-set TERMINFO, TERMINFO_DIRS and $HOME/.terminfo.
      envFilter = pkgs.writeCBin "nethogs-env-filter" ''
        #include <stdio.h>
        #include <string.h>
        #include <unistd.h>

        extern char **environ;

        static char real_prog[] = "${cfg.package}/bin/nethogs";
        /* The ncurses store database lacks system-profile entries such as xterm-kitty. */
        static char terminfo_dirs[] = "TERMINFO_DIRS=/run/current-system/sw/share/terminfo";

        int main(int argc, char **argv)
        {
          char *envp[3] = { terminfo_dirs, NULL, NULL };
          char **e;

          for (e = environ; *e != NULL; e++) {
            if (strncmp(*e, "TERM=", 5) == 0) {
              envp[1] = *e;
              break;
            }
          }

          /* execve(2) permits argc == 0, where argv[0] is the NULL terminator. */
          if (argc > 0)
            argv[0] = real_prog;
          execve(real_prog, argv, envp);
          perror(real_prog);
          return 127;
        }
      '';
    in
    {
      options.programs.nethogs.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nethogs.";
        };

        package = lib.mkPackageOption pkgs "nethogs" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        security.wrappers.nethogs = {
          source = "${envFilter}/bin/nethogs-env-filter";
          capabilities = "cap_sys_ptrace,cap_dac_read_search,cap_net_raw,cap_net_admin+ep";
          owner = "root";
          group = "wheel";
          permissions = "u+rx,g+x";
        };
      };
    };
in
{
  flake.nixosModules.apps.nethogs = NethogsModule;
}
