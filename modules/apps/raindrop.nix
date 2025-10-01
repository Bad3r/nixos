/*
  Package: raindrop
  Description: Electron wrapper for the Raindrop.io bookmark manager.
  Homepage: https://raindrop.io
  Documentation: https://help.raindrop.io

  Summary:
    * Launches the Raindrop.io progressive web application in a dedicated Electron shell.
    * Stores profile data under `~/.config/raindrop` to keep bookmarks and sessions isolated from other Electron apps.

  Example Usage:
    * `raindrop` — Open the Raindrop.io desktop experience in its own window.
*/

{
  config,
  ...
}:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.raindrop = pkgs.callPackage ../../packages/raindrop { };
    };

  flake.nixosModules.apps.raindrop =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        config.flake.packages.${pkgs.system}.raindrop
      ];
    };

  flake.homeManagerModules.apps.raindrop =
    { pkgs, ... }:
    {
      home.packages = [
        config.flake.packages.${pkgs.system}.raindrop
      ];
    };
}
