/*
  Package: libnotify
  Description: Library and CLI (`notify-send`) for sending freedesktop.org desktop notifications.
  Homepage: https://developer.gnome.org/libnotify/
  Documentation: https://developer-old.gnome.org/libnotify/unstable/
  Repository: https://gitlab.gnome.org/GNOME/libnotify

  Summary:
    * Provides a GLib-based API and the `notify-send` command to dispatch notifications compatible with daemons like dunst, GNOME Shell, or KDE plasma.
    * Supports urgency levels, icons, actions, and hints for controlling notification behavior.

  Options:
    notify-send <summary> [body]: Send a notification with optional body text.
    -u <low|normal|critical>: Set urgency.
    -t <timeout>: Specify timeout in milliseconds (0 for persistent).
    -i <icon>: Include an icon (by name or path).
    -a <appname>: Set the application name.

  Example Usage:
    * `notify-send "Build complete" "Artifacts are available in dist/"` — Send a simple desktop notification.
    * `notify-send -u critical -i dialog-warning "Backup failed"` — Emit a high urgency alert.
    * `notify-send -a deploy -t 0 "Deployment" "Waiting for confirmation"` — Display a persistent notification for manual actions.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.libnotify.extended;
  LibnotifyModule = {
    options.programs.libnotify.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable libnotify.";
      };

      package = lib.mkPackageOption pkgs "libnotify" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.libnotify = LibnotifyModule;
}
