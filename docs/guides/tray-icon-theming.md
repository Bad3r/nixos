# Tray Icon Theming (i3/i3bar)

Each i3-based host draws tray icons in `i3bar`, and whether an icon follows the active theme depends on how its app publishes it.

Scope: every host that runs the i3 session and the `vx` user. The i3 session is
enabled by importing `flake.nixosModules.i3` (wired in through
`modules/hosts/common/window-manager.nix` for hosts with `shareCommon = true`);
there is no `gui.i3.enable` toggle, and the `gui.i3` option tree only carries
session sub-options.

## Runtime Model

`i3bar` manages the tray, not `i3status-rust`:

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

- [Tray icon overrides](tray-icon-overrides.md)
- [Stylix Integration](stylix-integration.md)
- [Status Notifier Item Specification](https://specifications.freedesktop.org/status-notifier-item-spec/latest-single/)
- [Icon Theme Specification](https://xdg.pages.freedesktop.org/xdg-specs/icon-theme-spec/latest/)
