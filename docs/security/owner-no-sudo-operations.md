# Owner No-Sudo Operations

This page documents configuration-managed operations available to the system owner user without entering a sudo password.

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
- Disk management:
  - `fdisk ...`
  - mechanism:
    - `disk` group membership
  - available without sudo because owner is in the `disk` group.
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
  - available without sudo because packet capture is granted through capability-wrapped binaries rather than `sudo`.

## Commands That Are Passwordless With `sudo-rs`

- `sudo systemctl suspend`, `sudo reboot`, `sudo poweroff`
  - Granted by `NOPASSWD` wheel rule in `security.sudo-rs.extraRules`.

## Related

- Owner group privilege map:
  - [docs/security/owner-group-privileges.md](owner-group-privileges.md)

## Verification

- Commands:
  - `id -nG`
  - `journalctl -n 20 --no-pager`
  - `dmesg -T | head -n 20`
  - `nix eval --json .#nixosConfigurations.$(hostname).config.security.polkit.extraConfig | jq -r`
    - shows the enabled wheel power-off/reboot rule plus the NetworkManager/ModemManager
      group rules; only wheel rules are owned by `modules/security/polkit.nix`.
      Current host imports disable the optional wheel systemd unit-management rule.
  - `nix eval --json .#nixosConfigurations.$(hostname).config.security.sudo-rs.extraRules | jq`
