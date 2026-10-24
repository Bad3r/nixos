# Owner optional groups

Groups the owner profile in `modules/meta/owner.nix` leaves unassigned, and device groups a host can add on top of the baseline.

## Groups Defined But Not Assigned By Baseline Owner Profile

- `netdev`, `power`, `plugdev`, `bluetooth` are created in `modules/meta/owner.nix` but not assigned there.
- `netdev` note:
  - Avahi D-Bus policy grants `org.freedesktop.Avahi.Server.SetHostName` to `netdev` group members.
  - if owner is added to `netdev`, hostname change becomes available without sudo.
- `power` note:
  - on `songbird` the `power` group has no active grant because `thermald` is disabled.
  - on a host that enables `thermald`, its D-Bus policy grants the `power` group control of the daemon.
- `plugdev` / `bluetooth` note:
  - no direct owner assignment in baseline; privilege impact depends on service or udev rules that consume those groups.

## Common Optional Device Groups (Not In Baseline)

- `input`:

  - typical use:
    - low-level input automation, remapping, and event inspection via `/dev/input/event*`.
  - security impact:
    - keylogging/input capture and possible synthetic input abuse with emulation paths.

- `video`:

  - typical use:
    - direct webcam and DRM primary node access for low-level tooling.
  - security impact:
    - camera/device access outside stricter desktop portal mediation paths.

- `audio`:

  - typical use:
    - raw ALSA/JACK workflows that access `/dev/snd/*` directly.
  - security impact:
    - direct microphone/audio capture surface.

- `dialout`:

  - typical use:
    - serial and modem operations on `/dev/ttyS*` and USB serial adapters.
  - security impact:
    - direct control of attached serial devices.
