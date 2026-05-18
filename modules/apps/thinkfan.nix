/*
  Package: thinkfan
  Description: Simple fan-control daemon for ThinkPad and hwmon-compatible systems.
  Homepage: https://github.com/vmatare/thinkfan
  Documentation: https://github.com/vmatare/thinkfan
  Repository: https://github.com/vmatare/thinkfan

  Summary:
    * Enables the NixOS thinkfan service and installs the `thinkfan` command.
    * Uses the upstream NixOS ThinkPad defaults for tpacpi sensors, fan control, and fan levels.
    * Turns on the required `thinkpad_acpi` fan-control modprobe option through the upstream service module.

  Options:
    thinkfan -n: Run in foreground for manual troubleshooting.
    thinkfan -c <file>: Load an explicit thinkfan YAML configuration.
*/
_:
let
  ThinkfanModule =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.services.thinkfan.extended;
    in
    {
      options.services.thinkfan.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable thinkfan.";
        };
      };

      config = lib.mkIf cfg.enable {
        services.thinkfan.enable = true;
      };
    };
in
{
  flake.nixosModules.apps.thinkfan = ThinkfanModule;
}
