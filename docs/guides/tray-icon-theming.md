# Tray Icon Theming (i3/i3bar)

This guide documents how tray icons are managed on this host and how to make
them match the active theme.

Scope: single host (`system76`) and single user (`vx`).

## Runtime Model on This Host

Tray management is done by `i3bar`, not by `i3status-rust`:

- i3 bar config enables tray output on primary monitor:
  - `~/.config/i3/config` (`tray_output primary`)
- `i3status-rust` only provides status blocks via `status_command`.

Tray apps are launched as user services that depend on `tray.target`:

- `~/.config/systemd/user/network-manager-applet.service`
- `~/.config/systemd/user/udiskie.service`
- `~/.config/systemd/user/flameshot.service`

## What Is Actually Running

The active tray in this session is XEmbed-based (hosted by `i3bar`). Live
inspection of tray child windows under `i3bar` shows `_XEMBED_INFO` for:

- `nm-applet`
- `udiskie`
- `flameshot`
- `steam`
- `ktailctl`

No active `StatusNotifierWatcher`/SNI watcher was detected on the user bus in
this session.

## Protocol/Themeability Classification

| App       | Current Protocol | Themeability Risk | Notes                                                                                         |
| --------- | ---------------- | ----------------- | --------------------------------------------------------------------------------------------- |
| nm-applet | XEmbed           | Low-Medium        | Running without `--indicator`; links Ayatana indicator libs, but current tray item is XEmbed. |
| udiskie   | XEmbed           | Low               | Uses icon theme name lookup (`Gtk.IconTheme`) and supports custom `icon_names`.               |
| flameshot | XEmbed           | Medium            | Qt tray icon path supports theme lookup and also bundles fallback resources.                  |
| steam     | XEmbed           | High              | Tray icon behavior is app-controlled and often not fully theme-driven.                        |
| ktailctl  | XEmbed           | Medium            | Qt app; verify whether icon comes from theme name or bundled resource.                        |

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
2. If app uses icon names, override icon names in theme directories (prefer
   user-local `~/.local/share/icons`).
3. If app uses bundled bitmap/pixmap assets, use package-level patching
   (`overrideAttrs`, wrapper, patched resources), not direct `/nix/store` edits.
4. Refresh icon caches and restart the tray app (or relogin/restart i3bar).

For this host, prefer XEmbed-compatible launch mode (for example plain
`nm-applet`) unless you intentionally add an SNI bridge.

## Verification Commands

```bash
# Confirm i3 bar/tray config
i3-msg -t get_bar_config bar-0

# Confirm tray-related user services
systemctl --user list-dependencies --reverse tray.target

# Inspect i3bar children and tray windows (X11)
nix shell nixpkgs#xwininfo -c xwininfo -root -tree

# Verify a tray window uses XEmbed
xprop -id <window-id> _XEMBED_INFO WM_CLASS WM_NAME

# Check StatusNotifier watcher presence (SNI/AppIndicator path)
busctl --user list | rg -i 'statusnotifier|watcher|indicator'
```

## Related

- [Stylix Integration](stylix-integration.md)
- [Status Notifier Item Specification](https://specifications.freedesktop.org/status-notifier-item-spec/latest-single/)
- [Icon Theme Specification](https://xdg.pages.freedesktop.org/xdg-specs/icon-theme-spec/latest/)
