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
  cfg = config.programs.system.extended;
  SystemModule = {
    options.programs.system.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable system.";
      };

      package = lib.mkPackageOption pkgs "system" { };
    };

    config = lib.mkIf cfg.enable {
      nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "system" ];

      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.system = SystemModule;
}
