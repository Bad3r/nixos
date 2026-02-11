# Owner No-Sudo Operations

This page documents configuration-managed operations available to the system owner user without entering a sudo password.

Scope:

- owner and group assignment:
  - `modules/meta/owner.nix`
- polkit rules:
  - `modules/security/polkit.nix`
- sudo-rs rules:
  - `modules/system76/sudo.nix`
- kernel setting affecting `dmesg`:
  - `modules/system76/boot.nix`

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
    - polkit `networkmanager` group allow rules
  - Granted to `networkmanager` group by evaluated `security.polkit.extraConfig`.
- Log/kernel visibility:
  - `journalctl ...`
    - mechanism:
      - `systemd-journal` group membership
    - available without sudo because owner is in `systemd-journal`.
  - `dmesg ...`
    - mechanism:
      - `kernel.dmesg_restrict = 0`
    - available without sudo because `kernel.dmesg_restrict = 0`.

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
  - `nix eval --json .#nixosConfigurations.$(hostname).config.security.sudo-rs.extraRules | jq`
