# ActivityWatch

ActivityWatch records the active window and keyboard and mouse idle state, and charts them in a local web UI.
The web UI answers at `http://activitywatch.internal`.
The options and units live in [the NixOS module](../../../modules/apps/activitywatch/nixos.nix) and [the Home Manager module](../../../modules/apps/activitywatch/home.nix).

## Services

`aw-server`, `aw-watcher-afk`, and `aw-watcher-window` run as Home Manager user services under the graphical session.
The window watcher reads X11 window properties, so a Wayland session needs a different watcher such as `awatcher`.
Check them with:

```bash
systemctl --user status "activitywatch*"
```

## Name resolution

The name is a [loopback site](../../networking/loopback-sites.md) that rewrites the `Host` header to `127.0.0.1`.

```bash
getent hosts activitywatch.internal
```

## Privacy

Window titles and application names land in a local database under `~/.local/share/activitywatch`.
The window watcher drops password managers, Tor Browser, and mpv by window class and blanks private-browsing titles; the patterns sit in the Home Manager module.
Tracking browser tabs needs the `aw-watcher-web` extension, which the modules do not install.
