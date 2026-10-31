/*
  Package: libnotify
  Description: Library and CLI (`notify-send`) for sending freedesktop.org desktop notifications.
  Homepage: https://developer.gnome.org/libnotify/
  Documentation: https://developer-old.gnome.org/libnotify/unstable/
  Repository: https://gitlab.gnome.org/GNOME/libnotify

  Summary:
    * Provides a GLib-based API and the `notify-send` command to dispatch notifications to daemons like dunst, GNOME Shell, or KDE Plasma.
    * Supports urgency levels, icons, actions, and hints for controlling notification behavior.

  Options:
    -u <low|normal|critical>: Set urgency.
    -t <timeout>: Specify timeout in milliseconds (0 for persistent).
    -i <icon>: Include an icon (by name or path).
    -a <appname>: Set the application name.
*/
_:
let
  LibnotifyModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.libnotify.extended;
    in
    {
      options.programs.libnotify.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable libnotify.";
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
