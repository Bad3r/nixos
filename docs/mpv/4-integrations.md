# Integrations

mpv is the focal point of several adjacent integrations in this NixOS configuration: XDG MIME
defaults, MPRIS-driven media keys, an orthogonal codec bundle, a browser
bridge, and a custom playlist helper. This page walks each integration and
notes the boundary between it and the dedicated mpv module.

## XDG MIME and Default Applications

The `modules/xdg/` helpers expose a single source of truth for default
applications. The mpv-related entries are:

- `desktopFiles.audioPlayer.mpv` and `desktopFiles.videoPlayer.mpv`, both
  pointing at `mpv.desktop` and the `mpv` app module name.
- `defaultAppCategoryMeta.audioPlayer` and
  `defaultAppCategoryMeta.videoPlayer`, each defaulting to `"mpv"`.
- `videoPlayerMimeTypes` and `audioPlayerMimeTypes`, the canonical MIME-type
  lists fed to `mkMimeDefaults`.

The shared defaults module (`modules/hosts/common/default-apps.nix`) reads
these structures and emits parallel configurations:

- `xdg.mime.defaultApplications` (NixOS): System-wide `/etc/xdg/mimeapps.list` registers `mpv.desktop` for the audio/video MIME set.
- `home-manager.sharedModules.xdg.mimeApps.defaultApplications`: User-level `~/.config/mimeapps.list` carries the same mappings.
- `environment.variables.VIDEO_PLAYER` / `home.sessionVariables.VIDEO_PLAYER`: Exposes `VIDEO_PLAYER=mpv` to scripts that prefer env-driven dispatch.

The MIME-type lists themselves are exhaustive (covering matroska, webm, mp4,
opus, flac, etc.). Updating the list in the helper updates every consumer.

Setting `host.defaults.audioPlayer = "mpv"` or `videoPlayer = "mpv"` while
`programs.mpv.extended.enable` is `false` fails the build with the assertion
in `modules/hosts/common/default-apps.nix`; see [troubleshooting.md](6-troubleshooting.md)
for the failure mode and the two resolutions.

Only `videoPlayer` exports an environment variable (`VIDEO_PLAYER`), because
its `defaultAppCategoryMeta` entry in `modules/xdg/mime.nix` is the only one
of the two with an `extraConfig`. `audioPlayer` registers MIME defaults but
does not set an `AUDIO_PLAYER` env var.

## MPRIS and Media Keys

The HM module loads `mpvScripts.mpris`, which registers mpv on the standard
DBus MPRIS interface. Pairing it with the `playerctl` app module gives:

- Working desktop-environment media keys (play/pause, next, prev, stop).
- A `playerctl` CLI that can target mpv by name (`playerctl --player=mpv ...`).
- Metadata templates for status bars (`playerctl metadata --format ...`).

`mpvScripts.mpris` is declared in the HM module's `programs.mpv.scripts` list,
which wraps the mpv binary with `--script=` flags so the script loads at runtime.
See [scripts-and-bindings.md](3-scripts-and-bindings.md) for the full script
loading model.

## The `media-toolchain` Bundle

`modules/apps/media-toolchain.nix` installs a broad codec stack as a single
toggle:

- `pkgs.mpv`
- `pkgs.ffmpeg-full`
- `pkgs.imagemagick`, `pkgs.ghostscript`
- The `gst_all_1` plugin set (`gstreamer`, `gst-plugins-base`, `gst-plugins-good`, `gst-plugins-bad`, `gst-plugins-ugly`, `gst-libav`, `gst-vaapi`)

It is independent of the dedicated mpv app module. On hosts that enable the
bundle but disable the dedicated mpv module, the `mpv` binary is on `PATH` but
runs against upstream defaults with no managed `~/.config/mpv/` files. This
asymmetry is deliberate: the bundle exists to guarantee codec coverage for
ad-hoc workflows even where the curated mpv setup is not desired.

If a host needs both broad codec coverage and the managed mpv configuration,
enable both modules. The duplicate `pkgs.mpv` reference resolves to the same
store path; nothing is built twice.

## Browser Bridge: `open-in-mpv`

`open-in-mpv` is installed when `programs.mpv.extended.extras.openInMpv.enable` is `true` (the default). It
provides a small protocol handler and browser extension that dispatch web
videos to a running (or freshly launched) mpv instance. The package is
installed system-wide by the dedicated mpv module; pairing it with a browser
extension is a per-user choice and not modeled here.

## Playlist Helper: `video-cache`

`packages/video-cache/default.nix` defines a `writeShellApplication` that:

1. Scans a target directory for video files (using `fd`).
2. Runs `ffprobe` on each file to extract duration metadata, caching the
   result in `<dir>/.cache/video-durations.tsv`.
3. Filters by an optional duration range (`-d 3m:10m` for "between 3 and 10
   minutes", and so on).
4. Execs `mpv` (optionally with `--shuffle`) on the matching list.

The playlist is emitted in depth-first tree order, which is also the order the
cache file is stored in. Within a directory, entries sort case-insensitively
with natural number ordering, so `ep2.mkv` precedes `ep10.mkv`, and a
directory's contents stay contiguous rather than being split by a sibling file
that sorts between them. The ordering key is computed under `LC_ALL=C`, so it
does not shift with the caller's locale. Numeric runs have no fixed length
ceiling, and literal tabs are preserved through cache membership, pruning,
sorting, and playlist extraction. The cache remains line-based, so a filename
containing a newline is not representable; literal `\001` or `\002` bytes can
also order unpredictably because the transient key reserves those bytes for
directory separators and tab encoding. `-s` hands the list to `mpv --shuffle`
instead.

`checks."apps/video-cache-tree-order"` in `modules/apps/video-cache.nix` guards
that ordering, the alternate-locale invariant, long numeric runs, literal-tab
records including a leading tab in the cached path, cache mode preservation,
and cleanup of successful and failed replacements. Surviving prune records are
streamed through one cache-local temporary file before replacement. The locale
assertion uses a one-locale glibc archive rather than realizing the full locale
set. It stubs `ffprobe` and `mpv` through `callPackage`, so it builds neither,
and it is the only place CI reaches this package's `writeShellApplication`
shellcheck pass.

The helper is exposed as a custom package via
`modules/custom-overlays/video-cache.nix` (registering
`flake.customOverlays.video-cache`) and gated behind the standard
`programs.video-cache.extended.enable` option in `modules/apps/video-cache.nix`.
It is independent of the mpv app module: enabling `video-cache` on a host that
has mpv disabled installs the helper but `mpv` itself comes from
`media-toolchain` or the system path.

Run `video-cache --help` for the full list of flags. The cache and error log
live under `<video_dir>/.cache/`.

## Where to Look Next

- For the mpv configuration values themselves: [configuration.md](2-configuration.md).
- For extending or replacing any of these integrations on a single host:
  [customizing.md](5-customizing.md).
