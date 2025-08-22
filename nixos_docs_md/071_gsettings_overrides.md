## GSettings Overrides

Majority of software building on the GNOME platform use GLib’s [GSettings](https://developer.gnome.org/gio/unstable/GSettings.html) system to manage runtime configuration. For our purposes, the system consists of XML schemas describing the individual configuration options, stored in the package, and a settings backend, where the values of the settings are stored. On NixOS, like on most Linux distributions, dconf database is used as the backend.

[GSettings vendor overrides](https://developer.gnome.org/gio/unstable/GSettings.html#id-1.4.19.2.9.25) can be used to adjust the default values for settings of the GNOME desktop and apps by replacing the default values specified in the XML schemas. Using overrides will allow you to pre-seed user settings before you even start the session.

### Warning

Overrides really only change the default values for GSettings keys so if you or an application changes the setting value, the value set by the override will be ignored. Until [NixOS’s dconf module implements changing values](https://github.com/NixOS/nixpkgs/issues/54150), you will either need to keep that in mind and clear the setting from the backend using `dconf reset` command when that happens, or use the [module from home-manager](https://nix-community.github.io/home-manager/options.html#opt-dconf.settings).

You can override the default GSettings values using the [`services.desktopManager.gnome.extraGSettingsOverrides`](options.html#opt-services.desktopManager.gnome.extraGSettingsOverrides) option.

Take note that whatever packages you want to override GSettings for, you need to add them to [`services.desktopManager.gnome.extraGSettingsOverridePackages`](options.html#opt-services.desktopManager.gnome.extraGSettingsOverridePackages).

You can use `dconf-editor` tool to explore which GSettings you can set.

### Example

```programlisting
{
  services.desktopManager.gnome = {
    extraGSettingsOverrides = ''
      # Change default background

      [org.gnome.desktop.background]
      picture-uri='file://${pkgs.nixos-artwork.wallpapers.mosaic-blue.gnomeFilePath}'

      # Favorite apps in gnome-shell

      [org.gnome.shell]
      favorite-apps=['org.gnome.Console.desktop', 'org.gnome.Nautilus.desktop']
    '';

    extraGSettingsOverridePackages = [
      pkgs.gsettings-desktop-schemas # for org.gnome.desktop

      pkgs.gnome-shell # for org.gnome.shell

    ];
  };
}
```
