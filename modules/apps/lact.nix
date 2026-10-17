/*
  Package: lact
  Description: GPU monitoring and control daemon with a GTK front end, for AMD and NVIDIA cards.
  Homepage: https://github.com/ilya-zlobintsev/LACT
  Documentation: https://github.com/ilya-zlobintsev/LACT/wiki
  Repository: https://github.com/ilya-zlobintsev/LACT

  Summary:
    * Enables the NixOS lact service, which runs the `lactd` daemon and installs the `lact` GUI and CLI.
    * Sets power limits, fan curves, and clocks; on NVIDIA cards it works through NVML.

  Options:
    lact gui: Open the GUI.
    lact cli info: Show GPU details from the daemon.
    lact cli stats: Show GPU sensor readings.

  Example Usage:
    * `lact gui` -- Adjust power limits, fan curves, and clocks.
    * `lact cli stats` -- Print the current temperatures, clocks, and power draw.
*/
_:
let
  LactModule =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.services.lact.extended;
    in
    {
      options.services.lact.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable LACT.";
        };
      };

      config = lib.mkIf cfg.enable {
        services.lact.enable = true;
      };
    };
in
{
  flake.nixosModules.apps.lact = LactModule;
}
