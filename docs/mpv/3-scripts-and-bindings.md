# Scripts and Bindings

mpv auto-loads scripts only from `~/.config/mpv/scripts/` or from explicit `--script=<path>` flags baked into the binary.
The HM module builds the user's mpv from the row's package rewrapped with a script list, as the [package install contract](1-architecture.md#package-install-contract) describes, so every listed script loads through those flags.

- [Lua hooks](3-lua-hooks.md): the two repo-local scripts, `playlist_filter.lua` and `ytdlp_cookies.lua`.

## Script Loading Model

- `programs.mpv.extended.extraScripts` (NixOS): script packages the HM module appends to that script list, so they load at runtime.
- `programs.mpv.extended.extras.*` (NixOS): named enable options for bundled tools (`defaultShaders`, `openInMpv`, `jellyfinShim`), each installed through `environment.systemPackages`; not for scripts.
- `programs.mpv.extended.extraPackages` (NixOS): the additive escape hatch for tools not covered by `extras.*`, also installed through `environment.systemPackages`.
- `xdg.configFile."mpv/scripts/<name>.lua"` (HM): a raw Lua file dropped into `~/.config/mpv/scripts/`, which mpv loads at startup.

Home Manager's own `programs.mpv.scripts` stays empty, and a host that sets it fails the upstream assertion, so per-host scripts go through `extraScripts`.
[Adding scripts and bindings](5-customizing-scripts.md) has the usage patterns.

## MPV Bundled Scripts

These scripts load at startup.
`modernz`, `mpv-cheatsheet-ng`, `mpris`, `reload`, and the `mpv-image-viewer` sub-scripts are fixed in the HM module's script list, and `thumbfast` comes from the NixOS module's `extraScripts` default.

- `mpvScripts.modernz`: the replacement OSC, which draws the seek bar, volume control, and playback buttons.
  It replaces the built-in OSC and renders thumbnail previews from thumbfast when the cursor hovers over the seek bar.
- `mpvScripts.mpv-cheatsheet-ng`: an overlay listing all active keybindings, opened with `?`.
- `mpvScripts.mpris`: exports the standard MPRIS DBus interface, so desktop environments and `playerctl` can control playback and read metadata.
- `mpvScripts.reload`: watches stalled streams and re-issues the load when buffering hangs, instead of leaving mpv frozen on a dead segment.
- `mpvScripts.thumbfast`: generates seek-bar thumbnail previews on demand, which modernz reads from thumbfast's socket and draws inline.
- `mpvScripts.mpv-image-viewer.freeze-window`: keeps the window open after the last image in a playlist.
- `mpvScripts.mpv-image-viewer.image-positioning`: adds pan, zoom, and rotate controls for image files.
- `mpvScripts.mpv-image-viewer.status-line`: a persistent ASS overlay with the filename, playlist position (`[N/M]`), and image dimensions (`[WxH]`).
  It never auto-hides, so it stays dormant outside the `img` profile, as [Script Options](2-configuration.md#script-options) describes.

`mpvScripts.autoload`, which auto-queues the next file in the directory, sits commented out in the script list and loads only once the comment is removed.
[Adding scripts and bindings](5-customizing-scripts.md) covers enabling, disabling, or adding scripts.

## Keybindings

The HM module writes its bindings to `~/.config/mpv/input.conf` through `programs.mpv.bindings` in `modules/hm-apps/mpv/mpv.nix`, and mpv's other defaults stay available.

### Mapping Conventions

- `j` and `k` duplicate `h` and `l`, so all four vim-direction keys seek 5 seconds; volume stays on the scroll wheel.
- `h` and `l` are inverted relative to vim direction: `h` seeks forward and `l` backward, and `j` forward and `k` backward follow the same convention.
- `[` and `]` follow mpv's upstream defaults: `[` slows playback, and `]` speeds it up.

## Where to Look Next

- For settings written into `mpv.conf`: [configuration.md](2-configuration.md).
- For MIME wiring, MPRIS, and the media bundle: [integrations.md](4-integrations.md).
- For overriding scripts and bindings per host: [customizing.md](5-customizing.md).
