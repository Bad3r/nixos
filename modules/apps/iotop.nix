/*
  Package: iotop
  Description: Top-like I/O usage monitor for Linux displaying per-process read/write activity.
  Homepage: https://git.kernel.org/pub/scm/utils/iotop/iotop.git/
  Documentation: https://man7.org/linux/man-pages/man8/iotop.8.html
  Repository: https://git.kernel.org/pub/scm/utils/iotop/iotop.git

  Summary:
    * Displays real-time disk I/O for processes and threads using the taskstats kernel interface.
    * Supports cumulative and instantaneous modes, toggling by keys, and filtering by process.

  Options:
    -o, --only: Show processes actually doing I/O (default list includes idle ones).
    -b, --batch: Run in non-interactive batch mode suitable for logging.
    -n NUM: Number of iterations before exiting.
    -d SEC: Delay between iterations (default: 1 second).
    -p PID, --pid=PID: Monitor specific process IDs only.

  Example Usage:
    * `sudo iotop` — Display interactive per-process I/O statistics.
    * `sudo iotop -o -d 2` — Show only active I/O every two seconds.
    * `sudo iotop -b -n 10 > iotop.log` — Collect ten samples in batch mode for later analysis.
*/
_:
let
  IotopModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.iotop.extended;
    in
    {
      options.programs.iotop.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable iotop.";
        };

        package = lib.mkPackageOption pkgs "iotop" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.iotop = IotopModule;
}
