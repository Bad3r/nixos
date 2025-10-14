{ lib, ... }:
let
  gsettingsModule =
    {
      pkgs,
      lib,
      ...
    }:
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
        extraPortals = with pkgs; [
          xdg-desktop-portal-gtk
        ];
        config.common.default = "gtk";
      };
    };
in
{
  flake.nixosModules.roles.system.display.x11.imports = lib.mkAfter [ gsettingsModule ];
}
