/*
  Package: ltrace
  Description: Library call tracer for Linux that intercepts dynamically linked function calls and signals.
  Homepage: https://www.ltrace.org/
  Documentation: https://man7.org/linux/man-pages/man1/ltrace.1.html
  Repository: https://gitlab.com/cespedes/ltrace

  Summary:
    * Hooks shared-library calls made by a process, showing arguments, return values, and optionally system calls.
    * Debugs proprietary binaries and dynamic linking behavior without recompilation.

  Options:
    -f: Trace child processes (follow forks and execs).
    -n <num>: Control indentation depth for nested calls.
    -T: Display timing information for each call.
    -S: Trace system calls in addition to library calls.
    -e <expr>: Limit tracing to specific functions, libraries, or system calls.
*/
_:
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
          description = "Whether to enable ltrace.";
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
