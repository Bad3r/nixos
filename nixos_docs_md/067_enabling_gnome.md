## Enabling GNOME

All of the core apps, optional apps, games, and core developer tools from GNOME are available.

To enable the GNOME desktop use:

```programlisting
{
  services.desktopManager.gnome.enable = true;
  services.displayManager.gdm.enable = true;
}
```

### Note

While it is not strictly necessary to use GDM as the display manager with GNOME, it is recommended, as some features such as screen lock [might not work](#sec-gnome-faq-can-i-use-lightdm-with-gnome "Can I use LightDM with GNOME?") without it.

The default applications used in NixOS are very minimal, inspired by the defaults used in [gnome-build-meta](https://gitlab.gnome.org/GNOME/gnome-build-meta/blob/48.0/elements/core/meta-gnome-core-apps.bst).

### GNOME without the apps

If you’d like to only use the GNOME desktop and not the apps, you can disable them with:

```programlisting
{ services.gnome.core-apps.enable = false; }
```

and none of them will be installed.

If you’d only like to omit a subset of the core utilities, you can use [`environment.gnome.excludePackages`](options.html#opt-environment.gnome.excludePackages). Note that this mechanism can only exclude core utilities, games and core developer tools.

### Disabling GNOME services

It is also possible to disable many of the [core services](https://github.com/NixOS/nixpkgs/blob/b8ec4fd2a4edc4e30d02ba7b1a2cc1358f3db1d5/nixos/modules/services/x11/desktop-managers/gnome.nix#L329-L348). For example, if you do not need indexing files, you can disable TinySPARQL with:

```programlisting
{
  services.gnome.localsearch.enable = false;
  services.gnome.tinysparql.enable = false;
}
```

Note, however, that doing so is not supported and might break some applications. Notably, GNOME Music cannot work without TinySPARQL.

### GNOME games

You can install all of the GNOME games with:

```programlisting
{ services.gnome.games.enable = true; }
```

### GNOME core developer tools

You can install GNOME core developer tools with:

```programlisting
{ services.gnome.core-developer-tools.enable = true; }
```
