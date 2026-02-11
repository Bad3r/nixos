# Owner No-Sudo Operations

This page documents configuration-managed privileged operations available to the system owner user.

Scope:

- Owner identity source:
  - `lib/meta-owner-profile.nix`
  - `modules/meta/owner.nix`
- i7z implementation:
  - `modules/apps/i7z.nix`
- polkit rules:
  - `modules/security/polkit.nix`
- sudo-rs rules:
  - `security.sudo-rs.extraRules`

## Commands That Do Not Require `sudo` (polkit)

- Power commands:
  - `poweroff`, `reboot`
  - `systemctl poweroff`, `systemctl reboot`
  - Granted by polkit login1 actions for wheel group:
    - `org.freedesktop.login1.power-off*`
    - `org.freedesktop.login1.reboot*`
- NetworkManager and ModemManager commands:
  - `nmcli ...` privileged actions
  - `mmcli ...` privileged actions
  - Granted to `networkmanager` group by evaluated `security.polkit.extraConfig`.
- i7z:
  - `i7z`
  - Executed via owner-only `security.wrappers.i7z` with `cap_sys_rawio=ep` and controlled `/dev/cpu/*/msr` access.

## Commands That Are Passwordless With `sudo-rs`

- `sudo systemctl suspend`, `sudo reboot`, `sudo poweroff`
  - Granted by one `NOPASSWD` wheel rule in `security.sudo-rs.extraRules`.

## Wrapper Commands

Inspect current wrapper set:

```bash
➜ nix eval --json .#nixosConfigurations.$(hostname).config.security.wrappers | jq 'keys'
[
  "chsh",
  "dbus-daemon-launch-helper",
  "fusermount",
  "fusermount3",
  "i7z",
  "locate",
  "mount",
  "newgidmap",
  "newgrp",
  "newuidmap",
  "passwd",
  "pkexec",
  "plocate",
  "sg",
  "su",
  "sudo",
  "sudoedit",
  "umount",
  "unix_chkpwd"
]
```

NOTE: most are inherited from upstream

## i7z Implementation Logic

- Goal:
  - Run `i7z` without `sudo` while narrowing privilege scope.
- Design:
  - `security.wrappers.i7z` restricts execution to the owner account and applies `cap_sys_rawio=ep`.
  - `hardware.cpu.x86.msr` sets `/dev/cpu/*/msr` to `root:msr 0660`.
  - Owner account is added to `msr` group.
  - Activation script reapplies ownership and mode on switch/boot to correct stale device-node permissions.
- Rationale:
  - `i7z` checks write permission on MSR devices; `0660` is required for non-root operation.
  - Dedicated `msr` group reduces exposure compared with broad groups.
- Residual risk:
  - `cap_sys_rawio` remains high privilege; compromise of the owner account can abuse it.

## Verification

- Identity and group membership:
  - `whoami`
  - `id -nG`
- i7z wrapper and capability:
  - `ls -l /run/wrappers/bin/i7z`
  - `getcap /run/wrappers/bin/i7z`
- MSR device permissions:
  - `stat -c '%n %U:%G %a' /dev/cpu/0/msr`
- Evaluated policy:
  - `nix eval --json .#nixosConfigurations.$(hostname).config.security.polkit.extraConfig | jq -r`
  - `nix eval --json .#nixosConfigurations.$(hostname).config.security.sudo-rs.extraRules | jq`
