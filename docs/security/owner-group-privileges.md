# Owner Group Privileges

This page documents security-relevant access granted by owner group membership.

Scope:

- owner group baseline:
  - `modules/meta/owner.nix`
- extra owner groups from app/service modules:
  - example: `modules/apps/docker.nix`
- no-sudo command policy:
  - `modules/security/polkit.nix`
  - `modules/system76/sudo.nix`
  - `modules/system76/boot.nix`

## Groups Assigned To Owner In Baseline Profile

- `wheel`:
  - access:
    - full `sudo` access (password required by default)
    - passwordless `sudo` for:
      - `systemctl suspend`
      - `reboot`
      - `poweroff`
    - polkit allow for login1 power actions:
      - `org.freedesktop.login1.power-off*`
      - `org.freedesktop.login1.reboot*`
  - security impact:
    - administrative control path by design.

- `networkmanager`:
  - access:
    - polkit wildcard allow for:
      - `org.freedesktop.NetworkManager.*`
      - `org.freedesktop.ModemManager*`
    - enables privileged `nmcli` / `mmcli` operations without sudo.
  - security impact:
    - network tampering, DNS/profile changes, network DoS, and modem control if modem hardware exists.

- `systemd-journal`:
  - access:
    - read system journal via `journalctl` without sudo.
  - security impact:
    - logs may contain secrets, tokens, internal URLs, and sensitive error output.

- `adm`:
  - access:
    - traditional `/var/log` file read path (when files are group-readable by `adm`).
  - security impact:
    - same confidentiality concern as `systemd-journal`.
  - current host note:
    - most active logs are in `systemd-journal`; `adm` surface is smaller right now but can expand with service changes.

- `render`:
  - access:
    - GPU render nodes such as `/dev/dri/renderD*`.
  - security impact:
    - unprivileged GPU compute/acceleration surface.

- `lp`:
  - access:
    - printer/print-spool related paths (for example CUPS spool/cache files with `lp` group ownership).
  - security impact:
    - read/modify queued print jobs and printer-facing data.

## Additional Owner Groups Added By Other Modules

- `docker` (when Docker daemon module is enabled):
  - source:
    - `modules/apps/docker.nix`
  - access:
    - Docker socket control.
  - security impact:
    - effectively root-equivalent on the host.

## Groups Defined But Not Assigned By Baseline Owner Profile

- `netdev`, `power`, `plugdev`, `bluetooth` are created in `modules/meta/owner.nix` but not assigned there.
- `netdev` note:
  - Avahi D-Bus policy grants `org.freedesktop.Avahi.Server.SetHostName` to `netdev` group members.
  - if owner is added to `netdev`, hostname change becomes available without sudo.
- `power` note:
  - no direct polkit/dbus allow tied to `power` group is currently configured on this host.
- `plugdev` / `bluetooth` note:
  - currently no direct owner assignment in baseline; privilege impact depends on future service or udev rules that consume those groups.

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

## Audit Commands

- show evaluated owner groups:
  - `OWNER=$(nix eval --raw .#lib.meta.owner.username); nix eval --json .#nixosConfigurations.$(hostname).config.users.users.${OWNER}.extraGroups | jq`
- show active no-sudo rules:
  - `nix eval --json .#nixosConfigurations.$(hostname).config.security.polkit.extraConfig | jq -r`
  - `nix eval --json .#nixosConfigurations.$(hostname).config.security.sudo-rs.extraRules | jq`
- inspect runtime policy file:
  - `sed -n '1,220p' /etc/polkit-1/rules.d/10-nixos.rules`
- inspect runtime group-owned surfaces:
  - `find /dev -xdev -group input | head`
  - `find /dev -xdev -group video | head`
  - `find /dev -xdev -group audio | head`
  - `find /var -xdev -group systemd-journal | head`
