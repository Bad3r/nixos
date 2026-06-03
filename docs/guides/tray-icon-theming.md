# Tray Icon Theming (i3/i3bar)

This guide documents how tray icons are managed on each i3-based host in this
repo and how to make them match the active theme.

Scope: every host that runs the i3 session and the `vx` user. The i3 session is
enabled by importing `flake.nixosModules.i3` (wired in through
`modules/hosts/common/window-manager.nix` for hosts with `shareCommon = true`);
there is no `gui.i3.enable` toggle, and the `gui.i3` option tree only carries
session sub-options.

## Runtime Model

Tray management is done by `i3bar`, not by `i3status-rust`:

- i3 bar config enables tray output on primary monitor:
  - `~/.config/i3/config` (`tray_output primary`)
- `i3status-rust` only provides status blocks via `status_command`.
- `snixembed` owns `org.kde.StatusNotifierWatcher` on the user bus and bridges
  StatusNotifierItem/AppIndicator tray icons into the XEmbed tray hosted by
  `i3bar`.

Tray apps are launched as user services that depend on `tray.target`:

- `~/.config/systemd/user/snixembed.service`
- `~/.config/systemd/user/network-manager-applet.service`
- `~/.config/systemd/user/udiskie.service`
- `~/.config/systemd/user/flameshot.service`

## What Is Actually Running

The active tray remains XEmbed-based (hosted by `i3bar`). `snixembed` provides
the SNI watcher bridge so apps that only export StatusNotifierItem icons can
still show up in the `i3bar` tray.

Live inspection of tray child windows under `i3bar` distinguishes two groups.

Native XEmbed tray apps (own window, `_XEMBED_INFO` set on the application's
window):

- `nm-applet`
- `udiskie`
- `steam`
- `ktailctl`

SNI items proxied through `snixembed` (each has a `snixembed` child window
under `i3bar` whose `WM_CLASS` is the SNI `Id`):

- `flameshot` (`Id: flameshot`, `IconName: flameshot-tray`)
- `Remmina` (`Id: remmina-icon`, `IconName: org.remmina.Remmina-status`)
- `ProtonVPN`
- `teams-for-linux`

## Multi-Monitor Behavior

Keep the tray on `primary`. With the current i3/XEmbed stack there is one tray
selection owner, not one independent tray per monitor, so mirroring tray icons
across all connected outputs is not supported in a reliable way.

## Protocol/Themeability Classification

| App       | Current Protocol | Themeability Risk | Notes                                                                                                                |
| --------- | ---------------- | ----------------- | -------------------------------------------------------------------------------------------------------------------- |
| nm-applet | XEmbed           | Low-Medium        | Running without `--indicator`; links Ayatana indicator libs, but current tray item is XEmbed.                        |
| udiskie   | XEmbed           | Low               | Uses icon theme name lookup (`Gtk.IconTheme`); local Qogir-Dark override provides `drive-removable-media-usb-panel`. |
| steam     | XEmbed           | High              | Tray icon behavior is app-controlled and often not fully theme-driven.                                               |
| ktailctl  | XEmbed           | Medium            | Qt app; verify whether icon comes from theme name or bundled resource.                                               |
| flameshot | SNI via bridge   | Medium            | Qt SNI; advertises IconName `flameshot-tray`. Resolved by `snixembed` against the active Gtk theme.                  |
| NormCap   | Qt tray          | Low-Medium        | Qt resource aliases `:tray` and `:tray_done` are embedded in `resources.py`; the local module regenerates them.      |
| Remmina   | SNI via bridge   | Medium            | Ayatana SNI; advertises IconName `org.remmina.Remmina-status`. Icon files ship in `hicolor` (status context).        |
| ProtonVPN | SNI via bridge   | Low-Medium        | Local overlay rewrites tray states to the theme-provided `protonvpn-tray` icon name before `snixembed` proxies it.   |
| Teams     | SNI via bridge   | Low-Medium        | Electron tray image is bundled in `app.asar`; the local package override replaces those PNG assets directly.         |

## Broken Launcher Icons Found

Installed launcher audit found one broken icon reference:

- Desktop file:
  - `$XDG_DATA_HOME/applications/dev.heppen.webapps.NewQuickWebApp2293.desktop`
- App name:
  - `GitHub Notifications`
- Issue:
  - `Icon=$XDG_DATA_HOME/icons/QuickWebApps/NewQuickWebApp2293.svg`
  - Referenced file does not exist.

Fix by either:

1. Pointing `Icon=` to an existing absolute file, or
2. Switching `Icon=` to a theme icon name and adding/overriding that icon in
   your icon theme.

## Fix Strategy for i3bar/XEmbed

1. Confirm tray host and protocol first.
2. For SNI-only apps, confirm `snixembed` owns `org.kde.StatusNotifierWatcher`
   before debugging the application itself.
3. If app uses icon names, override icon names in theme directories (prefer
   user-local `$XDG_DATA_HOME/icons`).
4. If app uses bundled bitmap/pixmap assets, use package-level patching
   (`overrideAttrs`, wrapper, patched resources), not direct `/nix/store` edits.
5. Refresh icon caches and restart the tray app (or relogin/restart i3bar).

On the i3-based hosts, keep XEmbed-compatible launch mode for native tray apps
(for example plain `nm-applet`) and use the SNI bridge for apps that only
publish StatusNotifierItem icons.

## ProtonVPN Tray Icon

Upstream ProtonVPN starts with `IconName = proton-vpn-sign`, then switches tray
states to bundled absolute SVG paths such as `state-disconnected.svg`. Absolute
paths bypass Gtk icon-theme lookup, so they do not pick up the Qogir-Dark panel
style used by `flameshot-tray`.

The local ProtonVPN overlay (`modules/custom-overlays/proton-vpn.nix`) rewrites
the tray startup and connection-state icons to the theme-provided
`protonvpn-tray` icon name. `snixembed` then resolves that name through the
active Gtk icon theme, matching the same color/style path used by themed SNI
icons such as Flameshot.

The custom `protonvpn-tray` source lives at
`modules/stylix/icons/protonvpn-tray.svg`.

## NormCap Tray Icon

NormCap uses Qt resource aliases for the tray:

- `:tray`
- `:tray_done`

Those aliases are generated from `normcap/resources/icons/resources.qrc` into
`normcap/gui/resources.py`. Replacing the loose PNG files alone is not enough
because `QIcon(":tray")` and `QIcon(":tray_done")` read from the compiled Qt
resource data.

The local NormCap module (`modules/apps/normcap.nix`) renders the OneDark
sources from `modules/stylix/icons/normcap-tray.svg` and
`modules/stylix/icons/normcap-tray-done.svg` into the installed
`tray.png`/`tray_done.png` files, then regenerates `resources.py` with Qt's
resource compiler. The PNG render uses the same `11/16` glyph scale as the
Qogir-Dark panel icon generation so the tray glyph fits the rest of the custom
tray icon set.

## Teams for Linux Tray Icon

teams-for-linux has two icon surfaces:

- Launcher/window icons use the desktop icon name `teams-for-linux`. nixpkgs
  installs PNGs under `$out/share/icons/hicolor/<size>/apps/teams-for-linux.png`.
- Tray icons are selected by the Electron app from bundled files under
  `app/assets/icons/`. On Linux the default tray path uses `icon-96x96.png`;
  `appIconType = "light"` and `appIconType = "dark"` use the matching
  `icon-monochrome-*-96x96.png` files. The 16px variants are kept for the same
  selector on macOS and for completeness when upstream code paths change.

The local teams-for-linux module (`modules/apps/teams-for-linux.nix`) patches
the configured package after install. It renders the OneDark-adjusted source
logo from `modules/stylix/icons/teams-for-linux.svg` into hicolor launcher
sizes `16`, `24`, `32`, `48`, `64`, `96`, `128`, `256`, `512`, and `1024`,
and installs the scalable SVG variant.

The same override extracts and repacks `app.asar`, replacing all bundled tray
base icons with the panel-oriented OneDark source at
`modules/stylix/icons/teams-for-linux-tray.svg`. That tray source uses
OneDark `base05` (`#abb2bf`) for the glyph and `base00` (`#282c34`) for the
front tile letter, so it stays legible against the dark i3bar panel while
still matching the active palette. The tray PNG render uses the same `11/16`
glyph scale as the Qogir-Dark panel icon generation so the Electron tray image
does not fill the entire icon frame.

## udiskie Tray Icon

udiskie looks up tray icons through `Gtk.IconTheme`. Its default `media` icon
list starts with `drive-removable-media-usb-panel`, then falls back to the
stock Qogir-Dark removable-device icons.

The custom `drive-removable-media-usb-panel` source lives at
`modules/stylix/icons/udiskie-tray.svg`. It is derived from
`~/Downloads/usb.svg` and uses Qogir-Dark's panel text color (`#d3dae3`).
Its stroke is thickened before rendering so antialiasing does not make the tray
icon look dimmer than filled panel icons.

## Bridge Patches

`snixembed` is pinned to upstream 0.3.3 in nixpkgs. The custom overlay
(`modules/custom-overlays/snixembed.nix`) layers
`packages/snixembed/icon-resolution.patch` on top and wraps the binary with SVG
pixbuf support. The override addresses five defects:

1. `set_icon_pixmap` iterates the ARGB->RGBA conversion with `i += 3` over a
   4-byte buffer. The first pixel converts in place, then every later
   iteration overwrites the previous pixel's alpha with the next pixel's
   data. Fix: stride 4.
2. `set_icon` falls through to the pixmap path whenever
   `theme.has_icon(name)` returns false. Some SNI items omit `IconPixmap` or
   expose it with the wrong D-Bus type, and snixembed's generated Vala proxy
   can crash just by reading the property. Fix: only use the pixmap fallback
   when `IconPixmap` is already cached with the expected SNI array type.
3. ProtonVPN starts with a missing theme icon name (`proton-vpn-sign`) and
   later switches to an absolute SVG path. The guarded pixmap fallback lets Gtk
   render the named/file icon instead of aborting while probing ProtonVPN's
   malformed `IconPixmap`.
4. ProtonVPN can expose `ToolTip` as an empty string variant instead of the SNI
   tooltip tuple. The guarded tooltip read avoids aborting while the item is
   proxied into `i3bar`.
5. The upstream nixpkgs package is not wrapped with `librsvg`, so gdk-pixbuf
   cannot decode SVG status icons. The overlay adds `wrapGAppsHook3` and
   `librsvg`.

Drop the override once upstream `~steef/snixembed` ships a release past
0.3.3 with the equivalent fixes.

## Verification Commands

```bash
# Confirm i3 bar/tray config
i3-msg -t get_bar_config bar-0

# Confirm tray-related user services
systemctl --user list-dependencies --reverse tray.target

# Confirm the SNI bridge is running
systemctl --user status snixembed --no-pager

# Inspect i3bar children and tray windows (X11)
nix shell nixpkgs#xwininfo -c xwininfo -root -tree

# Verify a tray window uses XEmbed
xprop -id <window-id> _XEMBED_INFO WM_CLASS WM_NAME

# Check StatusNotifier watcher and bridged SNI items
busctl --user list | rg -i 'statusnotifierwatcher|snixembed|indicator|proton'
```

## Related

- [Stylix Integration](stylix-integration.md)
- [Status Notifier Item Specification](https://specifications.freedesktop.org/status-notifier-item-spec/latest-single/)
- [Icon Theme Specification](https://xdg.pages.freedesktop.org/xdg-specs/icon-theme-spec/latest/)
