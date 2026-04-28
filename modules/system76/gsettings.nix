{ lib, ... }:
{
  configurations.nixos.system76.module =
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
        # Screenshot=none lets flameshot fall back to its native XCB path
        # instead of blocking 30s on a portal call gtk no longer answers.
        config.i3 = {
          default = [ "gtk" ];
          "org.freedesktop.impl.portal.Screenshot" = "none";
        };
      };
    };
}
