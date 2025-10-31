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
  lib,
  pkgs,
  ...
}:
let
  RaindropModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.raindrop.extended;
    in
    {
      options.programs.raindrop.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable Raindrop.";
        };

        package = lib.mkPackageOption pkgs "raindrop" { };
      };

      config = lib.mkIf cfg.enable {
        nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "raindrop" ];

        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.raindrop = RaindropModule;
}
