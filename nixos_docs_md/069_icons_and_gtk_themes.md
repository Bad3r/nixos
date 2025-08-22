## Icons and GTK Themes

Icon themes and GTK themes don’t require any special option to install in NixOS.

You can add them to [`environment.systemPackages`](options.html#opt-environment.systemPackages) and switch to them with GNOME Tweaks. If you’d like to do this manually in dconf, change the values of the following keys:

```programlisting
/org/gnome/desktop/interface/gtk-theme
/org/gnome/desktop/interface/icon-theme
```

in `dconf-editor`
