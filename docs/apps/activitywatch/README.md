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

The module adds the name to `/etc/hosts` on loopback.
`.internal` keeps the lookup out of mDNS, which answers `.local` names first and never reads `/etc/hosts` on a miss.
nginx listens on loopback port 80 and proxies the name to the server, so the URL needs no port.
It rewrites the `Host` header to `127.0.0.1`, the only kind `aw-server` answers while it binds loopback.
Requests for any other name get no answer, which keeps the server's DNS-rebinding guard in place.

```bash
getent hosts activitywatch.internal
```

## Privacy

Window titles and application names land in a local database under `~/.local/share/activitywatch`.
The window watcher drops password managers, Tor Browser, and mpv by window class and blanks private-browsing titles; the patterns sit in the Home Manager module.
Tracking browser tabs needs the `aw-watcher-web` extension, which the modules do not install.
