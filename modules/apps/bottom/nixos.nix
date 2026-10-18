/*
  Package: bottom
  Description: Cross-platform graphical process/system monitor with a customizable interface.
  Homepage: https://github.com/ClementTsang/bottom
  Documentation: https://clementtsang.github.io/bottom/
  Repository: https://github.com/ClementTsang/bottom

  Summary:
    * Provides an interactive TUI dashboard with charts for CPU, memory, disks, processes, network, and temperature.
    * Ships the `btm` binary with support for custom layouts, theming, process management, and mouse interaction.

  Options:
    -b: Start in basic mode without graphs.
    -C: Load a specific configuration file overriding the default.
    -e: Expand the default widget on startup.
    --network_use_bytes: Display network widget in bytes instead of bits.
    --network_use_binary_prefix: Use binary prefixes (MiB, GiB) for the network widget.
*/
_:
let
  BottomModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.bottom.extended;
    in
    {
      options.programs.bottom.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable bottom.";
        };

        package = lib.mkPackageOption pkgs "bottom" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.bottom = BottomModule;
}
