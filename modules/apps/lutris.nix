/*
  Package: lutris
  Description: Open gaming platform for managing and launching games from multiple sources (native, Wine, emulators).
  Homepage: https://lutris.net/
  Documentation: https://github.com/lutris/docs/wiki
  Repository: https://github.com/lutris/lutris

  Summary:
    * Provides a unified library with installers for Wine, Steam, GOG, Epic, emulators, and custom runners, automating environment configuration.
    * Integrates community scripts, Vulkan/Esync optimizations, and per-game overrides for Wine versions, environment variables, and input tweaks.

  Options:
    lutris: Launch the GTK application and manage the game library.
    lutris -i <installer.yml>: Run a Lutris installer script from a YAML file or URL.
    lutris -d: Enable debug logging to stdout for troubleshooting runners.
    lutris -l: List installed games in the library from the command line.

  Example Usage:
    * `lutris` — Open the Lutris client to browse and launch games.
    * `lutris -i ~/Downloads/game.yml` — Install a game using a downloaded community installer script.
    * `lutris -d` — Start Lutris with verbose logs when diagnosing runner issues.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.lutris.extended;
  LutrisModule = {
    options.programs.lutris.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable lutris.";
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
