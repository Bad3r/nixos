/*
  Package: thinkfan
  Description: Simple fan-control daemon for ThinkPad and hwmon-compatible systems.
  Homepage: https://github.com/vmatare/thinkfan
  Documentation: https://github.com/vmatare/thinkfan
  Repository: https://github.com/vmatare/thinkfan

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
