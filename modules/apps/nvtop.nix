/*
  Package: nvtop
  Description: Interactive GPU process viewer and utilization monitor.
  Homepage: https://github.com/Syllo/nvtop
  Documentation: https://github.com/Syllo/nvtop#usage
  Repository: https://github.com/Syllo/nvtop

  Summary:
    * Plots GPU and memory utilization, clocks, temperature, power, and encode/decode load per device.
    * Lists processes holding GPU memory and can signal them from the interface.

  Options:
    -s --snapshot: Print current GPU stats as JSON without the ncurses interface.
    -i --gpu-info: Show the bar with additional GPU parameters.
    -d --delay <n>: Refresh interval in tenths of a second.
*/
_:
let
  NvtopModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.nvtop.extended;
    in
    {
      options.programs.nvtop.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nvtop.";
        };

        package = lib.mkPackageOption pkgs [ "nvtopPackages" "full" ] { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nvtop = NvtopModule;
}
