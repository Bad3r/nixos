/*
  Package: gdb
  Description: GNU Debugger for interactive debugging of programs and kernels.
  Homepage: https://www.gnu.org/software/gdb/
  Documentation: https://sourceware.org/gdb/current/onlinedocs/
  Repository: https://sourceware.org/git/?p=binutils-gdb.git

  Summary:
    * Offers source-level debugging for C, C++, Rust, Go, and more with breakpoints, watchpoints, and rich scripting APIs (Python/Guile).
    * Supports remote debugging, core file analysis, reverse debugging, and integration with TUI or IDE frontends.

  Options:
    --args <prog> [args...]: Launch a program with arguments under the debugger.
    -ex <command>: Execute a GDB command on startup (can be specified multiple times).
    -q: Start quietly without the banner.
    -p <pid>: Attach to an already running process by PID.
    -c <core>: Analyze a core dump alongside the original executable.

  Example Usage:
    * `gdb --args ./app --config config.toml` — Debug a program with custom arguments.
    * `gdb -p $(pidof myservice)` — Attach to a running service for live inspection.
    * `gdb -ex "break main" -ex run ./program` — Set a breakpoint at `main` before starting execution.
*/

{
  flake.nixosModules.apps.gdb =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gdb ];
    };

}
