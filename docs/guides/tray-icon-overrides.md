# Tray icon overrides

A tray app that bypasses the icon theme gets a package-level override that points its tray at a themed icon.

## ProtonVPN Tray Icon

Upstream ProtonVPN starts with `IconName = proton-vpn-sign`, then switches tray states to bundled absolute SVG paths such as `state-disconnected.svg`.
Absolute paths bypass Gtk icon-theme lookup, so they do not pick up the Qogir-Dark panel style used by `flameshot-tray`.

The local ProtonVPN overlay (`modules/apps/proton-vpn/overlay.nix`) rewrites the tray startup and connection-state icons to the theme-provided `protonvpn-tray` icon name.
`snixembed` then resolves that name through the active Gtk icon theme, the same color and style path that themed SNI icons such as Flameshot take.

The custom `protonvpn-tray` source lives at `modules/stylix/icons/protonvpn-tray.svg`.

## NormCap Tray Icon

NormCap uses Qt resource aliases for the tray:

- `:tray`
- `:tray_done`

Those aliases are generated from `normcap/resources/icons/resources.qrc` into `normcap/gui/resources.py`.
Replacing the loose PNG files alone is not enough, because `QIcon(":tray")` and `QIcon(":tray_done")` read from the compiled Qt resource data.

The local NormCap module (`modules/apps/normcap.nix`) renders the OneDark sources `modules/stylix/icons/normcap-tray.svg` and `modules/stylix/icons/normcap-tray-done.svg` into the installed `tray.png` and `tray_done.png`.
It then regenerates `resources.py` with Qt's resource compiler.
The PNG render uses the same `11/16` glyph scale as the Qogir-Dark panel icon generation, so the tray glyph fits the rest of the custom tray icon set.

## Teams for Linux Tray Icon

teams-for-linux has two icon surfaces:

- Launcher and window icons use the desktop icon name `teams-for-linux`, and nixpkgs installs PNGs under `$out/share/icons/hicolor/<size>/apps/teams-for-linux.png`.
- Tray icons come from bundled files under `app/assets/icons/`: on Linux the default tray path uses `icon-96x96.png`, and `appIconType = "light"` or `"dark"` uses the matching `icon-monochrome-*-96x96.png`.
  The 16px variants are kept for the same selector on macOS and in case upstream code paths change.

The local teams-for-linux module (`modules/apps/teams-for-linux.nix`) patches the configured package after install.
It renders the OneDark-adjusted source logo `modules/stylix/icons/teams-for-linux.svg` into the hicolor launcher sizes from `16` to `1024` and installs the scalable SVG variant.

The same override extracts and repacks `app.asar`, replacing every bundled tray base icon with the panel-oriented OneDark source `modules/stylix/icons/teams-for-linux-tray.svg`.
That source uses OneDark `base05` (`#abb2bf`) for the glyph and `base00` (`#282c34`) for the front tile letter, so it stays legible against the dark i3bar panel and matches the active palette.
The tray PNG render uses the same `11/16` glyph scale as the Qogir-Dark panel icon generation, so the Electron tray image does not fill the entire icon frame.

## udiskie Tray Icon

udiskie looks up tray icons through `Gtk.IconTheme`.
Its default `media` icon list starts with `drive-removable-media-usb-panel`, then falls back to the stock Qogir-Dark removable-device icons.

The custom `drive-removable-media-usb-panel` source lives at `modules/stylix/icons/udiskie-tray.svg` and uses Qogir-Dark's panel text color (`#d3dae3`).
Its stroke is thickened before rendering, so antialiasing does not make the tray icon look dimmer than filled panel icons.

## Bridge Patches

`snixembed` is pinned to upstream 0.3.3 in nixpkgs.
The custom overlay (`modules/apps/snixembed/overlay.nix`) layers `packages/snixembed/icon-resolution.patch` on top and wraps the binary with SVG pixbuf support.
The override addresses five defects:

1. `set_icon_pixmap` iterates the ARGB->RGBA conversion with `i += 3` over a 4-byte buffer, so every pixel after the first overwrites the previous pixel's alpha.
   The patch strides by 4.
2. `set_icon` falls through to the pixmap path whenever `theme.has_icon(name)` returns false, and the generated Vala proxy can crash reading an `IconPixmap` that is absent or has the wrong D-Bus type.
   The patch takes the pixmap path only when `IconPixmap` is already cached with the expected SNI array type.
3. ProtonVPN starts with a missing theme icon name (`proton-vpn-sign`) and later switches to an absolute SVG path.
   The guarded pixmap fallback lets Gtk render the named or file icon instead of aborting on ProtonVPN's malformed `IconPixmap`.
4. ProtonVPN can expose `ToolTip` as an empty string variant instead of the SNI tooltip tuple.
   The guarded tooltip read avoids aborting while the item is proxied into `i3bar`.
5. The upstream nixpkgs package is not wrapped with `librsvg`, so gdk-pixbuf cannot decode SVG status icons.
   The overlay adds `wrapGAppsHook3` and `librsvg`.

## Related

- [Tray Icon Theming (i3/i3bar)](tray-icon-theming.md)
- [Stylix Integration](stylix-integration.md)
