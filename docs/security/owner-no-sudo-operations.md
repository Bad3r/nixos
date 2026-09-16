# Owner No-Sudo Operations

Configuration-managed operations available to the system owner user without entering a sudo password.
Storage diagnostics carry their own capability wrappers and live on separate pages, linked under Related.

Scope:

- owner and group assignment:
  - `modules/meta/owner.nix`
- polkit rules:
  - `modules/security/polkit.nix`
- sudo-rs rules:
  - `modules/hosts/common/sudo.nix`
- kernel setting affecting `dmesg`:
  - `modules/hosts/common/boot.nix`

## Commands That Do Not Require `sudo`

- Power commands:
  - `poweroff`, `reboot`
  - `systemctl poweroff`, `systemctl reboot`
  - mechanism:
    - polkit wheel login1 actions
  - Granted by wheel login1 actions:
    - `org.freedesktop.login1.power-off*`
    - `org.freedesktop.login1.reboot*`
- NetworkManager/ModemManager commands:
  - `nmcli ...` privileged actions
  - `mmcli ...` privileged actions
  - mechanism:
    - polkit `networkmanager` group allow rules present in the evaluated
      `security.polkit.extraConfig`; the repo-owned `modules/security/polkit.nix`
      only owns wheel-group rules.
  - Available without sudo because the owner is in the `networkmanager` group
    (`modules/meta/owner.nix`).
- Log/kernel visibility:
  - `journalctl ...`
    - mechanism:
      - `systemd-journal` group membership
    - available without sudo because owner is in `systemd-journal`.
  - `dmesg ...`
    - mechanism:
      - `kernel.dmesg_restrict = 0`
    - available without sudo because `kernel.dmesg_restrict = 0`.
- Packet capture:
  - `wireshark`
  - `tcpdump`
  - selected `aircrack-ng` capture and injection binaries
  - mechanism:
    - `security.wrappers` with `CAP_NET_RAW` and `CAP_NET_ADMIN`
    - available to users in the `wheel` group
  - compatibility:
    - a `wireshark` group is also created and assigned to the owner user for tooling or policy that still expects it
  - limitation:
    - monitor-mode setup via `airmon-ng` is not capability-wrapped and still requires elevated setup
    - the `tcpdump` wrapper source is an argv filter that refuses `-z` for
      non-root callers. `tcpdump.c:3173` runs the postrotate command through
      `execlp()`, and the wrapper's ambient `CAP_NET_RAW` and `CAP_NET_ADMIN`
      land in that child. The filter rejects `-z` in any getopt form (`-z cmd`,
      `-nz cmd`, `-zcmd`, and after an operand, since glibc `getopt_long`
      permutes). Root callers retain the normal rotation and compression
      workflow; non-root callers should compress rotated files separately or
      reach the unwrapped `/run/current-system/sw/bin/tcpdump` without
      capabilities.
  - available without sudo because packet capture is granted through capability-wrapped binaries rather than `sudo`.

## Commands That Are Passwordless With `sudo-rs`

- `sudo systemctl suspend`, `sudo reboot`, `sudo poweroff`
  - Granted by `NOPASSWD` wheel rule in `security.sudo-rs.extraRules`.

## Related

- Owner group privilege map:
  - [owner-group-privileges.md](owner-group-privileges.md)
- Storage inspection and health reporting:
  - [owner-no-sudo-storage.md](owner-no-sudo-storage.md)
- NVMe subcommand allowlist:
  - [owner-no-sudo-nvme.md](owner-no-sudo-nvme.md)
- Self-encrypting drive management:
  - [owner-no-sudo-sed.md](owner-no-sudo-sed.md)

## Verification

- Commands:
  - `id -nG`
  - `journalctl -n 20 --no-pager`
  - `dmesg -T | head -n 20`
  - `nix eval --json .#nixosConfigurations.$(hostname).config.security.polkit.extraConfig | jq -r`
    - shows the enabled wheel power-off/reboot rule plus the NetworkManager/ModemManager
      group rules; only wheel rules are owned by `modules/security/polkit.nix`.
      The common host baseline disables the optional wheel systemd
      unit-management rule.
  - `nix eval --json .#nixosConfigurations.$(hostname).config.security.sudo-rs.extraRules | jq`
  - `tcpdump -c 1 -C 1 -w /tmp/cap -z /bin/true` as a non-root caller
    - should exit non-zero with `-z is refused by the capability wrapper`.
      A started capture means the argv filter was lost from
      `security.wrappers.tcpdump.source`.
  - `sudo tcpdump -c 1 -C 1 -w /tmp/cap -z /bin/true` as root, with a valid
    capture target
    - should not emit the wrapper refusal. A later capture or tcpdump error is
      from the real root execution path.
