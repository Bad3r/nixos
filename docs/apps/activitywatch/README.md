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
A `systemd-socket-proxyd` unit forwards the loopback web port to the server, so the URL needs no port.
The socket starts with `sockets.target` and the proxy service on the first request.
A switch never restarts a changed socket unit, so restart `activitywatch-http.socket` by hand after changing its address.

```bash
getent hosts activitywatch.internal
```

## Privacy

Window titles and application names land in a local database under `~/.local/share/activitywatch`.
The window watcher drops password managers entirely and blanks private-browsing titles; the patterns sit in the Home Manager module.
Tracking browser tabs needs the `aw-watcher-web` extension, which the modules do not install.
