/*
  Package: raindrop
  Description: Electron wrapper for the Raindrop.io bookmark manager.
  Homepage: https://raindrop.io
  Documentation: https://help.raindrop.io

  Summary:
    * Launches the Raindrop.io progressive web application in a dedicated Electron shell.
    * Stores profile data under `~/.config/raindrop` to keep bookmarks and sessions isolated from other Electron apps.

  Example Usage:
    * `raindrop` -- Open the Raindrop.io desktop experience in its own window.
*/
_:
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
          description = "Whether to enable Raindrop.";
        };

        package = lib.mkPackageOption pkgs "raindrop" { };
      };

      config = lib.mkIf cfg.enable {

        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "raindrop" ];
  flake.nixosModules.apps.raindrop = RaindropModule;
}
