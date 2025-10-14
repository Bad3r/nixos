/*
  Package: helvum
  Description: GTK patchbay for PipeWire multimedia routing.
*/

{
  flake.nixosModules.apps.helvum =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.helvum ];
    };
}
