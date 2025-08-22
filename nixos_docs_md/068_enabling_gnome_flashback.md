## Enabling GNOME Flashback

GNOME Flashback provides a desktop environment based on the classic GNOME 2 architecture. You can enable the default GNOME Flashback session, which uses the Metacity window manager, with:

```programlisting
{ services.desktopManager.gnome.flashback.enableMetacity = true; }
```

It is also possible to create custom sessions that replace Metacity with a different window manager using [`services.desktopManager.gnome.flashback.customSessions`](options.html#opt-services.desktopManager.gnome.flashback.customSessions).

The following example uses `xmonad` window manager:

```programlisting
{
  services.desktopManager.gnome.flashback.customSessions = [
    {
      wmName = "xmonad";
      wmLabel = "XMonad";
      wmCommand = "${pkgs.haskellPackages.xmonad}/bin/xmonad";
      enableGnomePanel = false;
    }
  ];
}
```
