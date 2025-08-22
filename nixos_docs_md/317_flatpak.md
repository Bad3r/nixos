## Flatpak

_Source:_ `modules/services/desktop/flatpak.nix`

_Upstream documentation:_ [https://github.com/flatpak/flatpak/wiki](https://github.com/flatpak/flatpak/wiki)

Flatpak is a system for building, distributing, and running sandboxed desktop applications on Linux.

To enable Flatpak, add the following to your `configuration.nix`:

```programlisting
{ services.flatpak.enable = true; }
```

For the sandboxed apps to work correctly, desktop integration portals need to be installed. If you run GNOME, this will be handled automatically for you; in other cases, you will need to add something like the following to your `configuration.nix`:

```programlisting
{
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  xdg.portal.config.common.default = "gtk";
}
```

Then, you will need to add a repository, for example, [Flathub](https://github.com/flatpak/flatpak/wiki), either using the following commands:

```programlisting
$ flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
$ flatpak update
```

or by opening the [repository file](https://flathub.org/repo/flathub.flatpakrepo) in GNOME Software.

Finally, you can search and install programs:

```programlisting
$ flatpak search bustle
$ flatpak install flathub org.freedesktop.Bustle
$ flatpak run org.freedesktop.Bustle
```

Again, GNOME Software offers graphical interface for these tasks.
