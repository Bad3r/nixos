# Owner No-Sudo Operations (system76)

This page documents configuration-managed privileged operations that the owner user (`vx`) can execute without being prompted for a sudo password.

Scope:

- Host: `system76`
- Owner profile: `lib/meta-owner-profile.nix`
- Owner module: `modules/meta/owner.nix`
- i7z privilege path: `modules/apps/i7z.nix`
- Power/systemd policy: `modules/security/polkit.nix`, `modules/system76/sudo.nix`

This is intentionally focused on repo-managed policy. It does not attempt to document every upstream setuid/setcap program shipped by all packages.

For host-level visibility of configured wrappers:

```bash
nix eval --json .#nixosConfigurations.system76.config.security.wrappers | jq 'keys'
```

## Direct Commands (No `sudo` Prefix Required)

These work because policy is delegated through `polkit` and group membership.

| Command examples                                                              | Why it works                                                                                                                           | Policy source                                                            |
| ----------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `poweroff`, `reboot`                                                          | Wheel members are granted login1 power actions through polkit (`org.freedesktop.login1.power-off*`, `org.freedesktop.login1.reboot*`). | `modules/security/polkit.nix`, enabled in `modules/system76/imports.nix` |
| `systemctl poweroff`, `systemctl reboot`                                      | Same login1 polkit action family as above.                                                                                             | `modules/security/polkit.nix`                                            |
| `systemctl start <unit>`, `systemctl stop <unit>`, `systemctl restart <unit>` | Wheel members are granted `org.freedesktop.systemd1.manage-units`.                                                                     | `modules/security/polkit.nix`, enabled in `modules/system76/imports.nix` |
| `nmcli ...` operations that require privileged NetworkManager actions         | `networkmanager` group is granted `org.freedesktop.NetworkManager.*` actions by polkit (from the evaluated host policy).               | Evaluated `security.polkit.extraConfig`                                  |
| `mmcli ...` operations that require ModemManager actions                      | `networkmanager` group is granted `org.freedesktop.ModemManager*` actions by polkit (from the evaluated host policy).                  | Evaluated `security.polkit.extraConfig`                                  |
| `i7z`                                                                         | Owner-only capability wrapper (`cap_sys_rawio`) + controlled `/dev/cpu/*/msr` access.                                                  | `modules/apps/i7z.nix`                                                   |

## Wrapper Commands Exposed By Host Configuration

At evaluation time on this host, `security.wrappers` includes:

- `chsh`
- `dbus-daemon-launch-helper`
- `fusermount`
- `fusermount3`
- `i7z`
- `locate`
- `mount`
- `newgidmap`
- `newgrp`
- `newuidmap`
- `passwd`
- `pkexec`
- `plocate`
- `sg`
- `su`
- `sudo`
- `sudoedit`
- `umount`
- `unix_chkpwd`

Most of these come from base system behavior or package defaults. The repo-specific hardening work in this change set is focused on `i7z` and power/systemd delegation.

## `sudo` Commands With No Password Prompt

These still use `sudo`, but are explicitly configured as `NOPASSWD` for wheel.

| Command examples         | Why it works                                           | Policy source               |
| ------------------------ | ------------------------------------------------------ | --------------------------- |
| `sudo systemctl suspend` | Explicit `security.sudo-rs.extraRules` NOPASSWD entry. | `modules/system76/sudo.nix` |
| `sudo reboot`            | Explicit `security.sudo-rs.extraRules` NOPASSWD entry. | `modules/system76/sudo.nix` |
| `sudo poweroff`          | Explicit `security.sudo-rs.extraRules` NOPASSWD entry. | `modules/system76/sudo.nix` |

## i7z Security Model And Implementation Logic

### Problem being solved

`i7z` reads Intel MSRs and checks write permission on `/dev/cpu/*/msr` before it starts. On this host, running plain `i7z` previously failed unless elevated.

### Implemented design

1. Keep `i7z` executable path restricted to the owner account via `security.wrappers.i7z`.
2. Grant `cap_sys_rawio=ep` only to that wrapper binary.
3. Enable `hardware.cpu.x86.msr` and set device ownership to `root` with mode `0660`.
4. Use a dedicated `msr` group instead of broad `users` group.
5. Add only the owner user to the `msr` group.
6. Re-apply `/dev/cpu/*/msr` owner/group/mode in an activation script so stale device-node permissions are corrected on switch/boot.

### Why this design

- `udev` owner assignment to a normal user is not reliable for this device class; using `owner = "root"` avoids that failure mode.
- `i7z` requires a write-permission check to pass, so mode `0660` is required for non-root usage.
- The dedicated `msr` group reduces exposure compared with `users` group access.
- Owner-only wrapper execution limits who can use the capability-bearing binary.

### Residual risk and boundary

- `cap_sys_rawio` is a high-privilege capability. If an attacker can execute as `vx`, they can run the wrapper.
- Risk is reduced by scope controls (owner-only wrapper, dedicated `msr` group) but not eliminated.

## How To Verify Current State

```bash
# Owner and groups
whoami
id -nG

# i7z wrapper restriction and capability
ls -l /run/wrappers/bin/i7z
getcap /run/wrappers/bin/i7z

# MSR device permissions
stat -c '%n %U:%G %a' /dev/cpu/0/msr

# Effective polkit and sudo policy from the evaluated host config
nix eval --json .#nixosConfigurations.system76.config.security.polkit.extraConfig | jq -r
nix eval --json .#nixosConfigurations.system76.config.security.sudo-rs.extraRules | jq
```
