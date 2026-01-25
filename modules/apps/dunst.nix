/*
  Package: dunst
  Description: Lightweight and highly configurable notification daemon for X11/Wayland.
  Homepage: https://dunst-project.org/
  Documentation: https://dunst-project.org/documentation/
  Repository: https://github.com/dunst-project/dunst

  Summary:
    * Implements the freedesktop.org notification specification with extensive theming, urgency handling, and scriptable hooks.
    * Supports dynamic configuration reloads, history, and integration with `dunstctl` for runtime control.

  Options:
    -config <file>: Load notifications settings from a specific dunstrc.
    -print: Output the current configuration and exit.
    -verbosity <level>: Adjust log verbosity (critical, error, warning, info, debug).
    dunstctl close-all: Close all displayed notifications via the companion CLI.
    dunstctl history-pop: Re-display the most recent notification from history.

  Example Usage:
    * `dunst -config ~/.config/dunst/dunstrc {PRESERVED_DOCUMENTATION}` -- Start dunst with a custom configuration file.
    * `dunstctl set-paused true` -- Temporarily pause displaying notifications.
    * `dunstctl history-pop` -- Quickly restore the last dismissed notification.
*/
_:
let
  DunstModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.dunst.extended;
    in
    {
      options.programs.dunst.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable dunst.";
        };

        package = lib.mkPackageOption pkgs "dunst" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.dunst = DunstModule;
}
