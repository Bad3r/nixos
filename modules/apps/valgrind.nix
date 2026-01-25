/*
  Package: valgrind
  Description: Instrumentation framework for memory debugging, profiling, and leak detection on Linux.
  Homepage: https://valgrind.org/
  Documentation: https://valgrind.org/docs/manual/manual.html
  Repository: https://sourceware.org/git/valgrind.git

  Summary:
    * Includes tools such as Memcheck (memory errors/leaks), Callgrind (profiling), Cachegrind (cache sim), Helgrind/DRD (thread errors), Massif (heap profiling).
    * Executes programs in a virtual CPU, providing detailed diagnostics for C/C++ and other native binaries.

  Options:
    valgrind --tool=memcheck <program>: Detect memory leaks and invalid accesses (default tool).
    valgrind --leak-check=full --show-leak-kinds=all: Provide detailed leak reports.
    valgrind --tool=callgrind <program>: Generate callgrind profiling data.
    valgrind --tool=massif <program>: Profile heap usage over time.
    valgrind --log-file=<path>: Save reports to a file per process.

  Example Usage:
    * `valgrind ./app` -- Run a binary under Memcheck to catch memory issues.
    * `valgrind --tool=callgrind ./app {PRESERVED_DOCUMENTATION}{PRESERVED_DOCUMENTATION} kcachegrind callgrind.out.*` -- Profile CPU hotspots and inspect results.
    * `valgrind --tool=massif --massif-out-file=massif.out ./server` -- Monitor heap growth for long-running services.
*/
_:
let
  ValgrindModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.valgrind.extended;
    in
    {
      options.programs.valgrind.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable valgrind.";
        };

        package = lib.mkPackageOption pkgs "valgrind" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.valgrind = ValgrindModule;
}
