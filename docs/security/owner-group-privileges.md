# Owner Group Privileges

This page documents security-relevant access granted by owner group membership.

Scope:

- owner group baseline:
  - `modules/meta/owner.nix`
- extra owner groups from app/service modules:
  - example: `modules/apps/docker.nix`
- no-sudo command policy:
  - `modules/security/polkit.nix`
  - `modules/hosts/common/sudo.nix`
  - `modules/hosts/common/boot.nix`

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
    - repo-owned `modules/security/polkit.nix` owns wheel-group polkit rules:
      - current host imports enable the power rule.
      - `wheelSystemdManagement` can grant
        `org.freedesktop.systemd1.manage-units`, but current host imports
        disable it.
    - packet-capture wrappers with `CAP_NET_RAW` / `CAP_NET_ADMIN` for:
      - Wireshark
      - `tcpdump`
      - selected `aircrack-ng` capture and injection binaries
  - security impact:
    - administrative control path by design.
    - also grants non-root packet capture through capability-wrapped binaries; `airmon-ng` monitor-mode setup is still outside that wrapper surface.

- `networkmanager`:

  - access:
    - polkit wildcard allow for:
      - `org.freedesktop.NetworkManager.*`
      - `org.freedesktop.ModemManager*`
    - enables privileged `nmcli` / `mmcli` operations without sudo.
    - present in the evaluated `security.polkit.extraConfig`; the repo-owned
      `modules/security/polkit.nix` only owns wheel-group rules.
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

- `disk`:

  - access:
    - raw block devices (e.g. `/dev/sda`, `/dev/nvme0n1`).
  - security impact:
    - full read/write access to storage devices, bypassing filesystem permissions. Allows running tools like `fdisk` without sudo.

## Additional Owner Groups Added By Other Modules

- `wireshark` (when Wireshark app module is enabled):

  - source:
    - `modules/apps/wireshark.nix`
  - access:
    - compatibility group membership for tooling or policy that expects the traditional `wireshark` group.
  - security impact:
    - limited direct impact in this repo because packet capture itself is granted through wheel-based capability wrappers.

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
  - on `system76` the `power` group has no active grant because `thermald` is disabled.
  - on hosts where `thermald` is enabled (for example `tpnix`), its D-Bus policy grants the `power` group control of the daemon.
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
  - `find /dev -xdev -group disk | head`
  - `find /var -xdev -group systemd-journal | head`
