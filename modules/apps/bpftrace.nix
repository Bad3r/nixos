/*
  Package: bpftrace
  Description: High-level tracing language for Linux eBPF.
  Homepage: https://bpftrace.org/
  Documentation: https://github.com/bpftrace/bpftrace/blob/master/man/adoc/bpftrace.adoc
  Repository: https://github.com/bpftrace/bpftrace

  Summary:
    * Compiles awk-like one-liners and scripts into eBPF programs attached to kprobes, uprobes, tracepoints, USDT probes, and perf events.
    * Aggregates kernel and user-space events into maps and histograms for syscall, scheduler, I/O, and network tracing.

  Options:
    -e '<program>': Run a one-liner.
    -l '<pattern>': List probes that match a pattern.
    -p <pid>: Limit tracing to one process.
    -o <file>: Write program output to a file.

  Notes:
    * Loading eBPF programs needs root. No capability wrapper exists, because bpftrace also demands `CAP_DAC_OVERRIDE` and `CAP_DAC_READ_SEARCH`, and `-c` and `--unsafe` would hand them to a child process.
    * A `NOPASSWD` sudo-rs rule lets `wheel` users run it as root without a password; the rule grants root, since `--unsafe` allows `system()`.
*/
_:
let
  BpftraceModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.bpftrace.extended;
    in
    {
      options.programs.bpftrace.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable bpftrace.";
        };

        package = lib.mkPackageOption pkgs "bpftrace" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        security.sudo-rs.extraRules = [
          {
            commands = [
              {
                command = "${cfg.package}/bin/bpftrace";
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
  flake.nixosModules.apps.bpftrace = BpftraceModule;
}
