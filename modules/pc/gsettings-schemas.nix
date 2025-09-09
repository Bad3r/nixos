_: {
  flake.nixosModules.pc =
    { pkgs, lib, ... }:
    {
      # Add GSettings desktop schemas for GTK/Electron applications
      environment.systemPackages = with pkgs; [
        gsettings-desktop-schemas
        glib # for gsettings command
        gtk3 # GTK3 schemas
        gtk4 # GTK4 schemas
        hicolor-icon-theme # Default icon theme
      ];

      # Ensure GIO modules are available
      services.udev.packages = with pkgs; [
        gsettings-desktop-schemas
      ];

      # Add schemas to DBus packages for proper registration
      services.dbus.packages = with pkgs; [
        gsettings-desktop-schemas
      ];

      # Essential environment variables for Electron/GTK apps
      environment.variables = {
        # Merge with existing GIO modules rather than overriding
        GIO_EXTRA_MODULES = lib.mkForce (
          lib.concatStringsSep ":" [
            "${pkgs.glib-networking}/lib/gio/modules"
            "${pkgs.gvfs}/lib/gio/modules"
            "${pkgs.dconf.lib}/lib/gio/modules"
          ]
        );
        GSETTINGS_SCHEMA_DIR = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas";
      };

      # Enable XDG portal for better desktop integration
      xdg.portal = {
        enable = true;
        extraPortals = with pkgs; [
          xdg-desktop-portal-gtk
        ];
      };
    };
}
