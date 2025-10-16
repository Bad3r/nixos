/*
  Package: qpwgraph
  Description: Qt patchbay for PipeWire connections.
*/

{
  flake.nixosModules.apps.qpwgraph =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.qpwgraph ];
    };
}
