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

  Notes:
    * A `NOPASSWD` sudo-rs rule lets `wheel` users run `gdb`, `gdbserver`, `gcore` as root, which attaches to processes that `kernel.yama.ptrace_scope = 1` shields from the owner.
*/
_:
let
  GdbModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.gdb.extended;
    in
    {
      options.programs.gdb.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable gdb.";
        };

        package = lib.mkPackageOption pkgs "gdb" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        security.sudo-rs.extraRules = [
          {
            commands = [
              {
                command = "${cfg.package}/bin/gdb";
                options = [ "NOPASSWD" ];
              }
              {
                command = "${cfg.package}/bin/gdbserver";
                options = [ "NOPASSWD" ];
              }
              {
                command = "${cfg.package}/bin/gcore";
                options = [ "NOPASSWD" ];
              }
            ];
            groups = [ "wheel" ];
          }
        ];
      };
    };
in
{
  flake.nixosModules.apps.gdb = GdbModule;
}
