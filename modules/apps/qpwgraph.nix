/*
  Package: qpwgraph
  Description: Qt patchbay that draws the PipeWire graph and edits its links.
  Homepage: https://gitlab.freedesktop.org/rncbc/qpwgraph
  Documentation: https://gitlab.freedesktop.org/rncbc/qpwgraph#qpwgraph
  Repository: https://gitlab.freedesktop.org/rncbc/qpwgraph

  Summary:
    * Shows audio, MIDI, and video nodes with their ports, and connects or disconnects them by drag and drop.
    * Saves patchbays, sets of connections that an active patchbay restores as nodes appear.

  Options:
    [patchbay-file]: Load a saved .qpwgraph patchbay at start.
    -a, --activated: Start with the patchbay activated.
    -x, --exclusive: Make the patchbay exclusive, so links it does not list are removed.
    -m, --minimized: Start minimized.
    -r, --remote <name>: Connect to the named PipeWire remote daemon.

  Example Usage:
    * `qpwgraph` -- Open the PipeWire graph.
    * `qpwgraph -a -m ~/studio.qpwgraph` -- Start minimized with a saved patchbay active.
*/
_:
let
  QpwgraphModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.qpwgraph.extended;
    in
    {
      options.programs.qpwgraph.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable qpwgraph.";
        };

        package = lib.mkPackageOption pkgs "qpwgraph" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.qpwgraph = QpwgraphModule;
}
