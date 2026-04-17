# Tray Icon Theming (i3/i3bar)

This guide documents how tray icons are managed on this host and how to make
them match the active theme.

Scope: single host (`system76`) and single user (`vx`).

## Runtime Model on This Host

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

Live inspection of tray child windows under `i3bar` shows `_XEMBED_INFO` for
native XEmbed tray apps such as:

- `nm-applet`
- `udiskie`
- `flameshot`
- `steam`
- `ktailctl`

SNI-only apps such as ProtonVPN should expose `org.kde.StatusNotifierItem-*` on
the user bus and be proxied into that same XEmbed tray by `snixembed`.

## Multi-Monitor Behavior

Keep the tray on `primary`. With the current i3/XEmbed stack there is one tray
selection owner, not one independent tray per monitor, so mirroring tray icons
across all connected outputs is not supported in a reliable way.

## Protocol/Themeability Classification

| App       | Current Protocol | Themeability Risk | Notes                                                                                         |
| --------- | ---------------- | ----------------- | --------------------------------------------------------------------------------------------- |
| nm-applet | XEmbed           | Low-Medium        | Running without `--indicator`; links Ayatana indicator libs, but current tray item is XEmbed. |
| udiskie   | XEmbed           | Low               | Uses icon theme name lookup (`Gtk.IconTheme`) and supports custom `icon_names`.               |
| flameshot | XEmbed           | Medium            | Qt tray icon path supports theme lookup and also bundles fallback resources.                  |
| steam     | XEmbed           | High              | Tray icon behavior is app-controlled and often not fully theme-driven.                        |
| ktailctl  | XEmbed           | Medium            | Qt app; verify whether icon comes from theme name or bundled resource.                        |
| ProtonVPN | SNI via bridge   | Medium            | Exports a StatusNotifierItem; `snixembed` proxies it into the XEmbed tray hosted by `i3bar`.  |

## Broken Launcher Icons Found

Installed launcher audit found one broken icon reference:

- Desktop file:
  - `~/.local/share/applications/dev.heppen.webapps.NewQuickWebApp2293.desktop`
- App name:
  - `GitHub Notifications`
- Issue:
  - `Icon=/home/vx/.local/share/icons/QuickWebApps/NewQuickWebApp2293.svg`
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
   user-local `~/.local/share/icons`).
4. If app uses bundled bitmap/pixmap assets, use package-level patching
   (`overrideAttrs`, wrapper, patched resources), not direct `/nix/store` edits.
5. Refresh icon caches and restart the tray app (or relogin/restart i3bar).

For this host, keep XEmbed-compatible launch mode for native tray apps (for
example plain `nm-applet`) and use the SNI bridge for apps that only publish
StatusNotifierItem icons.

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
