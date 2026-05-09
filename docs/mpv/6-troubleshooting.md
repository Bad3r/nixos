# Troubleshooting

Known failure modes and their resolutions.

## Codec Not Supported

### Symptom

Playback fails with "no decoder for codec ..." on a file that other systems
play correctly.

### Cause

The minimal nixpkgs `mpv` build covers the common open codec set but not
every patent-encumbered or downstream-distributed codec. The
`media-toolchain` module installs a broader stack (ffmpeg-full, GStreamer
plugin sets) that fills most gaps.

### Resolution

Enable the `media-toolchain` app module on the host. See
[integrations.md](4-integrations.md). If the file still fails, it is likely a
codec that is not in nixpkgs at all and must be supplied via a custom build.

## MIME Default Assertion Fails

### Symptom

`nix flake check` (or a host build) fails with an assertion message like:

```
<host>.defaults.videoPlayer is set to "mpv" but the app module is not enabled.
Enable it with: programs.mpv.extended.enable = true;
Or set <host>.defaults.videoPlayer = null; to disable this default.
```

The same assertion exists for `audioPlayer`.

### Cause

The host declares mpv as the default audio or video handler in
`modules/<host>/default-apps.nix`, but the dedicated mpv module is disabled.
The XDG default-apps machinery refuses to register `mpv.desktop` as the MIME
handler for `audio/*` or `video/*` types when the matching app module would
not otherwise install mpv. The assertion lives in `modules/<host>/default-apps.nix`
and is parameterized by the category name.

### Resolution

Pick one:

- Enable the app module: `programs.mpv.extended.enable = true;`.
- Or drop the default for that category: `<host>.defaults.videoPlayer = null;`
  (and `audioPlayer` if it points at mpv too).

The assertion is intentional; it prevents shipping an XDG mimeapps entry that
points at a desktop file the host never installed.

## Hardware Decode Falls Back to Software Silently

### Symptom

CPU usage is high during playback even though `hwdec=auto` is set; `mpv -v`
shows the software decoder being used.

### Cause

`hwdec=auto` negotiates at runtime and falls back when no path is available.
Common reasons:

- The GPU driver is not installed or not loaded.
- The user is not in the `video` group (or the analogous group that grants
  access to `/dev/dri/*`).
- The codec is not in the GPU's hardware-decode whitelist.

### Resolution

Run mpv with `--hwdec-codecs=all -v` against a known-supported codec to confirm
the negotiation. Inspect the GPU enablement modules in the host configuration
to confirm the relevant kernel module and userspace driver are present.

## Where to Look Next

- For the keys that drive these behaviors: [configuration.md](2-configuration.md).
- For overriding any of them on a single host: [customizing.md](5-customizing.md).
- For the integration points that interact with mpv: [integrations.md](4-integrations.md).
