/*
  Package: biome
  Description: Fast formatter and linter for the JavaScript/TypeScript ecosystem.
*/

{
  flake.nixosModules.apps.biome =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.biome ];
    };
}
