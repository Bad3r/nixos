# Lua Hooks

The HM module ships two repo-local Lua scripts, rendered by `modules/apps/mpv/scripts.nix` into script packages (`flake.lib.homeManager.mpvScripts`).
The HM module adds both to the script list it rewraps the row's package with, so they load alongside the bundled `mpvScripts.*` packages through the same `--script=` flags.
Nothing is written to `~/.config/mpv/scripts/`; the loading model is in [Scripts and Bindings](3-scripts-and-bindings.md).

## `playlist_filter.lua`

Filters playlist entries by file type.
It starts in `off` mode, with no filtering; `F3` cycles through the modes at runtime, and the startup mode is set without rebuilding Nix:

- Named profiles in `mpv.conf`: `mpv --profile=vid ...` (or `mpv -p vid ...`) skips image files, and `mpv --profile=img ...` (or `mpv -p img ...`) is the image viewer; [Profiles](2-configuration.md#profiles) has their settings.
- Wrappers installed as user packages: `mpv-vid`, shorthand for `mpv --profile=vid`, and `mpv-img`, shorthand for `mpv --profile=img`.
- Direct flag: `mpv --script-opts=playlist_filter-mode=block-images ...` or `mpv --script-opts=playlist_filter-mode=images-only ...`.
- Persistent default, which the module does not write: `~/.config/mpv/script-opts/playlist_filter.conf` containing the line below.

```text
mode=block-images
```

The modes are `off` (default), `block-images`, and `images-only`.
The `F3` runtime cycle works on top of whichever startup mode is active, and the mode resets to the startup value on the next mpv invocation.

Override the keybinding in `input.conf`:

```text
F3 script-binding playlist_filter-cycle
```

## `ytdlp_cookies.lua`

The script resolves a browser at mpv startup and appends `cookies-from-browser=<browser>` to `ytdl-raw-options`.
Streaming URLs that need session cookies, such as members-only videos or region-locked content, then authenticate with the active browser profile.
Resolution order:

- `MPV_YTDLP_BROWSER`, the dedicated override: a browser name forces the value, and the empty string disables cookie passthrough entirely.
- `$BROWSER`, set by the XDG defaults machinery: the fallback when `MPV_YTDLP_BROWSER` is unset, so it picks up the host's default web browser.
- `--ytdl-raw-options=cookies-from-browser=<browser>` on the mpv command line: the script detects it, treats it as authoritative, and suppresses its own append.

With neither variable set and no flag passed, the script logs at verbose level and leaves `ytdl-raw-options` untouched, so mpv runs without cookies rather than failing.
