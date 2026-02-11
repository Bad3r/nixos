/*
  Package: i7z
  Description: Better i7 (and now i3, i5) reporting tool for Linux.
  Homepage: https://github.com/DimitryAndric/i7z
  Documentation: https://github.com/DimitryAndric/i7z
  Repository: https://github.com/DimitryAndric/i7z

  Summary:
    * Shows per-core CPU frequencies, multipliers, and C-state residency in real time.
    * Supports socket-specific monitoring and logging frequency samples for later analysis.

  Options:
    --nogui: Turn off the ncurses interface output.
    -w, --write <a|l>: Write samples to a log file in append or replace mode.
    -l, --logfile <path>: Use a custom log file path instead of the default filename.
    --socket0 <id>: Select which socket ID to display as the primary package.
    --socket1 <id>: Select a secondary socket ID for dual-socket monitoring.

  Notes:
    * Does not install a capability wrapper; running `i7z` requires explicit elevation.
    * Enables `hardware.cpu.x86.msr` because i7z reads model-specific registers.
*/
_:
let
  I7zModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.i7z.extended;
    in
    {
      options.programs.i7z.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable i7z.";
        };

        package = lib.mkPackageOption pkgs "i7z" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        # Keep MSR support enabled for root-run i7z, with default restrictive
        # permissions managed by the upstream x86-msr module.
        hardware.cpu.x86.msr.enable = true;
      };
    };
in
{
  flake.nixosModules.apps.i7z = I7zModule;
}
