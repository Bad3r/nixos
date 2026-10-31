/*
  Package: dunst
  Description: Lightweight and highly configurable notification daemon for X11/Wayland.
  Homepage: https://dunst-project.org/
  Documentation: https://dunst-project.org/documentation/
  Repository: https://github.com/dunst-project/dunst

  Summary:
    * Implements the freedesktop.org notification specification with theming, urgency rules, and scriptable hooks.
    * Keeps a notification history and takes runtime control through `dunstctl`.

  Options:
    -config <file>: Load settings from a specific dunstrc.
    -print: Print notifications to stdout.
    -verbosity <level>: Set the minimum log level (critical, error, warning, info, debug).
    dunstctl close-all: Close all displayed notifications.
    dunstctl history-pop: Re-display the most recent notification from history.
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
