/*
  Package: strace
  Description: Diagnostic and debugging tool that monitors system calls and signals made by a process.
  Homepage: https://strace.io/
  Documentation: https://man7.org/linux/man-pages/man1/strace.1.html
  Repository: https://github.com/strace/strace

  Summary:
    * Attaches to running processes or launches new ones, tracing system calls, arguments, return values, and signals for debugging and auditing.
    * Supports filtering by syscall, attaching to multiple processes, generating timestamps, and decoding complex structures like ioctl and network calls.

  Options:
    strace <command>: Trace a command from startup.
    -p <pid>: Attach to an existing process.
    -f: Follow forked processes.
    -e trace=<syscall_set>: Filter system calls (e.g. `trace=network,file`).
    -tt -T: Print timestamps and syscall durations.

  Example Usage:
    * `strace ls` — View system calls made by `ls`.
    * `sudo strace -p 1234 -f -o trace.log` — Attach to PID 1234, following forks, and log to a file.
    * `strace -e trace=network curl example.com` — Inspect only network-related system calls for a command.
*/
_:
let
  StraceModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.strace.extended;
    in
    {
      options.programs.strace.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable strace.";
        };

        package = lib.mkPackageOption pkgs "strace" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.strace = StraceModule;
}
