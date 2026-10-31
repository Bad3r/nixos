/*
  Package: raindrop
  Description: Electron wrapper for the Raindrop.io bookmark manager.
  Homepage: https://raindrop.io
  Documentation: https://help.raindrop.io
  Repository: nil

  Notes:
    * Profile lives in `~/.config/raindrop`.
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
  flake.nixosModules.apps.raindrop = RaindropModule;
}
