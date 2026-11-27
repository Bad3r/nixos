# Owner No-Sudo Operations

Configuration-managed operations available to the system owner user without entering a sudo password.
Raw storage tools are not among them; they run under `sudo`.

Scope:

- owner and group assignment:
  - `modules/meta/owner.nix`
- polkit rules:
  - `modules/security/polkit.nix`
- sudo-rs rules:
  - `modules/hosts/common/sudo.nix`
  - `modules/apps/bpftrace.nix`
  - `modules/apps/gdb.nix`, `modules/apps/strace.nix`, `modules/apps/ltrace.nix`, `modules/apps/frida-tools.nix`, and `modules/apps/delve.nix`
- kernel setting affecting `dmesg`:
  - `modules/hosts/common/boot.nix`

## Commands That Do Not Require `sudo`

Linger is the exception: `loginctl enable-linger` and `disable-linger` fail for every non-root caller.
`modules/meta/owner.nix` declares the owner's linger off.
`modules/security/polkit.nix` denies `org.freedesktop.login1.set-self-linger` and `org.freedesktop.login1.set-user-linger`.

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
      owns only the wheel-group rules and the linger denial.
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
  - mechanism:
    - `security.wrappers` with `CAP_NET_RAW` and `CAP_NET_ADMIN`
    - available to users in the `wheel` group
  - compatibility:
    - a `wireshark` group is also created and assigned to the owner user for tooling or policy that still expects it
  - limitation:
    - `aircrack-ng`'s live-capture and injection binaries are not wrapped, because their shared Linux osdep backend shells out with the caller-supplied interface name on every card open (`do_linux_open()`), which would hand that shell the wrapper's ambient capabilities (`modules/apps/aircrack-ng.nix`, issue #475).
    - use `sudo` for `airbase-ng`, `aireplay-ng`, `airodump-ng`, `airserv-ng`, `airtun-ng`, `besside-ng`, `easside-ng`, `tkiptun-ng`, and `wesside-ng`.
    - `airmon-ng` is also unwrapped and still requires elevated setup for monitor mode.
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
- Per-process bandwidth monitoring:
  - `bandwhich`
  - `nethogs`
  - mechanism:
    - `security.wrappers` in `modules/apps/bandwhich.nix` and `modules/apps/nethogs.nix` with `CAP_NET_RAW`, `CAP_NET_ADMIN`, `CAP_SYS_PTRACE`, and `CAP_DAC_READ_SEARCH`
    - available to users in the `wheel` group
  - `CAP_SYS_PTRACE` and `CAP_DAC_READ_SEARCH` cover reading every process's `/proc/<pid>/fd`, which maps sockets to processes.
  - limitation:
    - the `nethogs` wrapper source passes only `TERM` and a `TERMINFO_DIRS` pinned to `/run/current-system/sw/share/terminfo`, since ambient capabilities leave ncurses honoring caller-set terminfo paths.
      A terminal entry that only `~/.terminfo` or a per-user profile provides fails to load.

## Commands That Are Passwordless With `sudo-rs`

- `sudo systemctl suspend`, `sudo reboot`, `sudo poweroff`
  - Granted by `NOPASSWD` wheel rule in `security.sudo-rs.extraRules`.
- `sudo bpftrace ...`
  - Granted by a `NOPASSWD` wheel rule in `modules/apps/bpftrace.nix`, present only where the app is enabled.
  - The rule matches the binary with any arguments and runs it as root.
    `-c <cmd>` and `--unsafe` (`system()`) start root commands, so the rule is a passwordless root for `wheel` users.
  - No capability wrapper exists, because bpftrace refuses to start without `CAP_DAC_OVERRIDE` and `CAP_DAC_READ_SEARCH` on top of `CAP_BPF` and `CAP_PERFMON`, and `-c` and `--unsafe` would pass them to a child process.
- Attaching to a running process:
  - `sudo gdb`, `sudo gdbserver`, `sudo gcore`
  - `sudo strace`, `sudo ltrace`
  - `sudo frida`, `sudo frida-trace`, `sudo frida-strace`, `sudo frida-itrace`, `sudo frida-discover`
  - `sudo dlv`, `sudo dlv-dap`
  - Granted by one `NOPASSWD` wheel rule per app module, present only where the app is enabled.
  - `kernel.yama.ptrace_scope = 1` lets a process attach only to its own descendants unless the caller has `CAP_SYS_PTRACE`; root has it, so these rules remove the password prompt for attaching to any process.
  - Each rule runs the tool as root with any arguments, so every one is a passwordless root: `gdb -ex 'shell ...'`, `strace` with `-o`, and `frida` scripts all run as root.
  - Launching the target as a child (`strace -f <cmd>`, `gdb --args <cmd>`) needs no privilege, and these rules do not change that.
  - A tool run under `sudo` skips the owner's `~/.gdbinit` and other per-user configuration.

## Related

- Owner group privilege map:
  - [owner-group-privileges.md](owner-group-privileges.md)
- Storage device access:
  - [owner-storage-access.md](owner-storage-access.md)

## Verification

- Commands:
  - `id -nG`
  - `journalctl -n 20 --no-pager`
  - `dmesg -T | head -n 20`
  - `nix eval --json .#nixosConfigurations.$(hostname).config.security.polkit.extraConfig | jq -r`
    - shows the enabled wheel power-off/reboot rule, the linger denial, and the
      NetworkManager/ModemManager group rules; `modules/security/polkit.nix` owns
      the wheel and linger rules.
      The common host baseline disables the optional wheel systemd
      unit-management rule.
  - `nix eval --json .#nixosConfigurations.$(hostname).config.security.sudo-rs.extraRules | jq`
    - lists the power rule and, where bpftrace is enabled, the `bpftrace` rule.
  - `tcpdump -c 1 -C 1 -w /tmp/cap -z /bin/true` as a non-root caller
    - should exit non-zero with `-z is refused by the capability wrapper`.
      A started capture means the argv filter was lost from
      `security.wrappers.tcpdump.source`.
  - `sudo tcpdump -c 1 -C 1 -w /tmp/cap -z /bin/true` as root, with a valid
    capture target
    - should not emit the wrapper refusal. A later capture or tcpdump error is
      from the real root execution path.
