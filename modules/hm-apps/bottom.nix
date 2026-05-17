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

  Notes:
    * Per-widget single-view configs (cpu, mem, net, disk, temp, proc) are written to
      $XDG_CONFIG_HOME/bottom/ for use with btm-* shell aliases.
    * Package installation is handled by the NixOS module; package = null avoids double-installation.
*/

_: {
  flake.homeManagerModules.apps.bottom =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "bottom" "extended" "enable" ] false osConfig;
      widgetConfig = type: ''
        [[row]]
          [[row.child]]
            type = "${type}"
      '';
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.bottom = {
          enable = true;
          package = null;
        };

        home.shellAliases = {
          btm-cpu = "btm -C ~/.config/bottom/cpu.toml";
          btm-mem = "btm -C ~/.config/bottom/mem.toml";
          btm-net = "btm -C ~/.config/bottom/net.toml";
          btm-disk = "btm -C ~/.config/bottom/disk.toml";
          btm-temp = "btm -C ~/.config/bottom/temp.toml";
          btm-proc = "btm -C ~/.config/bottom/proc.toml";
        };

        xdg.configFile = {
          "bottom/cpu.toml".text = widgetConfig "cpu";
          "bottom/mem.toml".text = widgetConfig "mem";
          "bottom/net.toml".text = widgetConfig "net";
          "bottom/disk.toml".text = widgetConfig "disk";
          "bottom/temp.toml".text = widgetConfig "temp";
          "bottom/proc.toml".text = widgetConfig "proc";
        };
      };
    };
}
