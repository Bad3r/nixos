{ lib, ... }:
let
  # D-Bus activation can precede the i3 session environment import, so the
  # fail-closed map applies to both the generic and i3 portal profiles.
  portalPreferences = {
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

  body =
    { config, pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        gsettings-desktop-schemas
        glib
        gtk3
        gtk4
        hicolor-icon-theme
      ];

      services = {
        udev.packages = with pkgs; [
          gsettings-desktop-schemas
        ];

        dbus.packages = with pkgs; [
          gsettings-desktop-schemas
        ];

        # Adds the TLS GIO module dir via sessionVariables, list-merged with the dconf
        # and gvfs modules; a forced string here would diverge from /etc/pam/environment.
        gnome.glib-networking.enable = true;
      };

      # Keep the host-enabled Secret mapping coupled to its portal provider.
      assertions = [
        {
          assertion =
            !(builtins.elem "gnome-keyring" (
              lib.toList (portalPreferences."org.freedesktop.impl.portal.Secret" or "none")
            ))
            || !config.services.gnome.gnome-keyring.enable
            || builtins.elem pkgs.gnome-keyring config.xdg.portal.extraPortals;
          message =
            "org.freedesktop.impl.portal.Secret is pinned to gnome-keyring, but "
            + "gnome-keyring.portal is not in xdg.portal.extraPortals; with default=none "
            + "the Secret portal is unexported.";
        }
      ];

      # Unwrapped GTK programs (nix-ld foreign binaries, devshell scripts) reach schemas
      # only via XDG_DATA_DIRS; these entries rank below a wrapGAppsHook --prefix.
      environment.sessionVariables.XDG_DATA_DIRS = map (p: "${p}/share/gsettings-schemas/${p.name}") (
        with pkgs;
        [
          gsettings-desktop-schemas
          gtk3
          gtk4
        ]
      );

      # gdk-pixbuf builds its own loaders in; the SVG loader is third-party, and the
      # icon themes here ship SVG only. Same session-wide cache the xfce module uses.
      programs.gdk-pixbuf.modulePackages = [ pkgs.librsvg ];

      xdg.portal = {
        enable = true;
        extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
        config = lib.genAttrs [ "common" "i3" ] (_: portalPreferences);
      };
    };
in
{
  # Keep the parity check's expected set tied to the map rendered below
  # without re-evaluating a host configuration from a flake-level check.
  flake.lib.nixos._portalPreferences = portalPreferences;
  flake.nixosModules.hosts-common.imports = [ body ];
}
