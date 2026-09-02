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
  - `modules/hosts/common/storage-diagnostics.nix`
  - `modules/apps/smartmontools.nix`
  - `modules/apps/nvme-cli.nix`
  - `modules/apps/hdparm.nix`
  - `modules/apps/sedutil.nix`

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
      - the common host baseline enables the power rule.
      - `wheelSystemdManagement` can grant
        `org.freedesktop.systemd1.manage-units`, but the common host baseline
        disables it.
    - packet-capture wrappers with `CAP_NET_RAW` / `CAP_NET_ADMIN` for:
      - Wireshark
      - `tcpdump`
      - selected `aircrack-ng` capture and injection binaries
  - security impact:
    - administrative control path by design.
    - also grants non-root packet capture through capability-wrapped binaries; `airmon-ng` monitor-mode setup is still outside that wrapper surface.
    - the `tcpdump` wrapper source refuses `-z` for non-root capability-wrapper
      execution, because `tcpdump.c:3173` `execlp`s the postrotate command with
      the ambient capability set intact. Root callers retain the normal
      rotation and compression workflow.

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
    - NVMe controller and generic char devices (`/dev/nvme0`, `/dev/ng0n1`) via
      the shared udev rule in `modules/hosts/common/storage-diagnostics.nix`.
    - storage diagnostic wrappers with `CAP_SYS_ADMIN` / `CAP_SYS_RAWIO` for:
      - `smartctl`
      - `nvme`
      - `sedutil-cli`
      - `hdparm` (when the hdparm app module is enabled; disabled on tpnix)
  - security impact:
    - full read/write access to storage devices, bypassing filesystem permissions. Allows running tools like `fdisk` without sudo.
    - the `smartctl` wrapper is filtered. It retains capabilities only for
      audited reports, the documented `-v`/`--vendorattribute` display
      definitions and `-F`/`--firmwarebug` report workarounds, read-only settings
      and log queries (including bare `-n sleep`, `-n standby`, and `-n idle`
      power-mode checks), and the standard `offline`, `short`, `long`, and
      `conveyance` self-tests documented by the module. SMART configuration
      (`-s`, `-o`, `-S`, and `--set`), log resets or writes,
      selective/pending/force/captive/abort tests, and unknown forms clear the
      ambient set and need `sudo`.
    - the `hdparm` wrapper retains capabilities only for short-option clusters made from `-C`, `-g`, `-i`,
      `-I`, `-t`, and `-T`. Standalone input formatting such as `--Istdin` also
      takes the cleared-capability path, but reads and formats stdin only,
      opens no device, and needs neither storage capabilities nor `sudo`. ATA
      Security, DCO/HPA, raw-sector writes, TRIM, sanitize, firmware,
      device-setting, unknown, and parameter-bearing options clear the ambient
      set and need `sudo`.
      Raw block reads and writes remain available through `disk` membership,
      but that does not grant the separate ATA Security, DCO, or HPA control
      paths.
    - the `nvme` wrapper is not whole-binary. Its source allowlists the
      read-only diagnostic subcommands plus two whose state change is the
      diagnostic itself, `device-self-test`, whose options can start or abort
      a drive self-test, and `telemetry-log`, whose default run has the
      controller capture fresh host-initiated telemetry in place of the
      retained capture, and clears the ambient capability set before `execve`
      for everything else. `nvme format`, `nvme sanitize`, `nvme fw-commit`,
      raw `nvme get-log`, and the vendor plugins therefore run without
      `CAP_SYS_ADMIN` and need `sudo` again. `nvme help` also runs on the
      cleared path without the storage capability, although it may fail if
      the manual page is unavailable. See
      [docs/security/owner-no-sudo-operations.md](owner-no-sudo-operations.md)
      for the allowlist and the `system()` injection sites that motivate it.
    - for the sedutil 1.49.13 parser, the `sedutil-cli` wrapper is also
      filtered. It retains capabilities only for `--scan` and its JSON output
      forms, `--query` and its JSON output forms with one device,
      `--isValidSED <device>`, and `--printDefaultPassword <device>`. Opal
      password, locking-range, PBA, and revert actions clear the ambient set
      and need `sudo` again. `--printDefaultPassword` exposes the drive MSID
      and should be treated as credential material. The filter checks the first
      action and relies on sedutil's exact and maximum argument checks to reject
      later actions before dispatch; re-audit a custom package if that parser
      changes.

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
