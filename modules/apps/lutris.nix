/*
  Package: lutris
  Description: Open gaming platform for managing and launching games from multiple sources (native, Wine, emulators).
  Homepage: https://lutris.net/
  Documentation: https://github.com/lutris/docs/wiki
  Repository: https://github.com/lutris/lutris

  Summary:
    * Provides a unified library with installers for Wine, Steam, GOG, Epic, emulators, and custom runners.
    * Integrates community install scripts and per-game overrides for Wine versions, environment variables, and input.

  Options:
    lutris -i <installer.yml>: Run a Lutris installer script from a YAML file or URL.
    lutris -d: Enable debug logging to stdout for troubleshooting runners.
    lutris -l: List installed games in the library from the command line.
*/
_:
let
  LutrisModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.lutris.extended;
    in
    {
      options.programs.lutris.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable lutris.";
        };

        package = lib.mkPackageOption pkgs "lutris" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.lutris = LutrisModule;
}
