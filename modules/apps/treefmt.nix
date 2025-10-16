/*
  Package: treefmt
  Description: Multi-language formatting orchestrator with declarative config support.
*/

{
  flake.nixosModules.apps.treefmt =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.treefmt ];
    };
}
