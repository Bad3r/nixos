/*
  Package: ltrace
  Description: Library call tracer for Linux that intercepts dynamically linked function calls and signals.
  Homepage: https://www.ltrace.org/
  Documentation: https://man7.org/linux/man-pages/man1/ltrace.1.html
  Repository: https://github.com/munin-monitoring/ltrace

  Summary:
    * Hooks shared-library calls made by a process, showing arguments, return values, and optionally system calls.
    * Useful for debugging proprietary binaries, reverse engineering, or understanding dynamic linking behavior without recompilation.

  Options:
    -f: Trace child processes (follow forks and execs).
    -n <num>: Control indentation depth for nested calls.
    -T: Display timing information for each call.
    -S: Trace system calls in addition to library calls.
    -e <expr>: Limit tracing to specific functions, libraries, or system calls.

  Example Usage:
    * `sudo ltrace ./app` — Inspect shared-library calls made by `app`.
    * `ltrace -f -e malloc+free ./binary` — Follow forks and show only allocation-related calls.
    * `ltrace -S -o trace.log command` — Trace both library and system calls, saving results to a log file.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  LtraceModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.ltrace.extended;
    in
    {
      options.programs.ltrace.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable ltrace.";
        };

        package = lib.mkPackageOption pkgs "ltrace" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.ltrace = LtraceModule;
}
