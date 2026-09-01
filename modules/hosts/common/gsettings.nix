{ lib, ... }:
let
  body =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        gsettings-desktop-schemas
        glib
        gtk3
        gtk4
        hicolor-icon-theme
      ];

      services.udev.packages = with pkgs; [
        gsettings-desktop-schemas
      ];

      services.dbus.packages = with pkgs; [
        gsettings-desktop-schemas
      ];

      environment.variables = {
        GIO_EXTRA_MODULES = lib.mkForce (
          lib.concatStringsSep ":" [
            "${pkgs.glib-networking}/lib/gio/modules"
            "${pkgs.gvfs}/lib/gio/modules"
            "${pkgs.dconf.lib}/lib/gio/modules"
          ]
        );
        GSETTINGS_SCHEMA_DIR = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas";
      };

      xdg.portal = {
        enable = true;
        extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
        config.i3 = {
          default = "none";

          "org.freedesktop.impl.portal.Access" = "gtk";
          "org.freedesktop.impl.portal.Account" = "gtk";
          "org.freedesktop.impl.portal.AppChooser" = "gtk";
          "org.freedesktop.impl.portal.DynamicLauncher" = "gtk";
          "org.freedesktop.impl.portal.Email" = "gtk";
          "org.freedesktop.impl.portal.FileChooser" = "gtk";
          "org.freedesktop.impl.portal.Inhibit" = "gtk";
          "org.freedesktop.impl.portal.Lockdown" = "gtk";
          "org.freedesktop.impl.portal.Notification" = "gtk";
          "org.freedesktop.impl.portal.Print" = "gtk";
          "org.freedesktop.impl.portal.Settings" = "gtk";
          "org.freedesktop.impl.portal.Wallpaper" = "gtk";

          "org.freedesktop.impl.portal.Secret" = "gnome-keyring";

          "org.freedesktop.impl.portal.Background" = "none";
          "org.freedesktop.impl.portal.Clipboard" = "none";
          "org.freedesktop.impl.portal.GlobalShortcuts" = "none";
          "org.freedesktop.impl.portal.InputCapture" = "none";
          "org.freedesktop.impl.portal.RemoteDesktop" = "none";
          "org.freedesktop.impl.portal.ScreenCast" = "none";
          "org.freedesktop.impl.portal.Screenshot" = "none";
          "org.freedesktop.impl.portal.Usb" = "none";
        };
      };
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
