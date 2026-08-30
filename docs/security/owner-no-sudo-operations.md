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
- storage capability wrappers:
  - `modules/apps/smartmontools.nix`
  - `modules/apps/nvme-cli.nix`
  - `modules/apps/hdparm.nix`
  - `modules/apps/sedutil.nix`
- shared NVMe char-device udev rule and its retrigger unit:
  - `modules/hosts/common/storage-diagnostics.nix`

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
- Partition and device inventory:
  - `fdisk ...`, `lsblk ...`, `blkid ...`
    - always present: `util-linux` is in the nixpkgs `corePackageNames` base
      system, not an app module.
  - `parted ...` (when the parted app module is enabled; disabled on tpnix)
  - mechanism:
    - `disk` group membership
  - available without sudo because block device nodes are `root:disk 0660` and
    owner is in the `disk` group.
- Storage health diagnostics:
  - `smartctl ...`
  - `nvme ...`
  - `hdparm ...` (when the hdparm app module is enabled; disabled on tpnix)
  - mechanism:
    - `security.wrappers` with `CAP_SYS_ADMIN` (`nvme`) or `CAP_SYS_ADMIN` plus
      `CAP_SYS_RAWIO` (`smartctl`, `hdparm`)
    - available to users in the `disk` group
  - why group membership alone is not enough:
    - `nvme_cmd_allowed()` rejects NVMe admin passthrough
      (`NVME_IOCTL_ADMIN_CMD`) without `CAP_SYS_ADMIN`, so SMART, error, and
      firmware logs fail with `Permission denied` even on a device node the
      caller can open.
    - the SG_IO command filter rejects ATA passthrough without `CAP_SYS_RAWIO`,
      which is what makes `smartctl -d sat` report
      `Read Device Identity failed: Operation not permitted` on SATA disks.
    - `ata_sas_scsi_ioctl()` requires both capabilities for `HDIO_DRIVE_CMD`,
      the ioctl behind `hdparm -I`.
  - NVMe char devices:
    - a shared udev rule in `modules/hosts/common/storage-diagnostics.nix` sets
      `GROUP="disk"` and `MODE="0660"` on the `nvme` and `nvme-generic`
      subsystems, because the kernel default of `root:root 0600` on
      `/dev/nvme0` and `/dev/ng0n1` is a DAC check that no capability in the
      wrapper set overrides. Only the namespace block nodes (`/dev/nvme0n1`)
      carry `disk` by default.
    - the same module runs a `nvme-char-device-permissions` oneshot that
      retriggers both subsystems. A switch only restarts `systemd-udevd`, and
      udev applies rules to new uevents only, so nodes enumerated at boot would
      otherwise keep `root:root 0600` until a reboot. `udevadm trigger` needs
      root, which the `disk` members this grant targets do not have.
  - why the wrapper sources are argv filters:
    - `security.wrappers` raises the configured capabilities into the process
      ambient set (`nixos/modules/security/wrappers/wrapper.c:137`). An ambient
      capability survives `execve` of an ordinary file and lands in the child's
      effective set, so any subprocess the wrapped binary starts inherits it.
      The filter is a compiled binary, never a shell script: a capability
      wrapper is not setuid, so `euid == uid`, bash does not enter privileged
      mode, and `BASH_ENV` is absent from glibc's `unsecvars.h`.
  - limitation:
    - the `smartctl` and `hdparm` wrappers cover whole binaries, so destructive
      flags (`hdparm --security-erase`, `--trim-sector-ranges`,
      `--make-bad-sector`) are passwordless for `disk` members too. `disk`
      membership already permits raw writes to the same devices, so this widens
      the blast radius of a typo rather than the privilege boundary.
    - the `nvme` wrapper is not whole-binary. Its source allowlists the
      read-only diagnostic subcommands (`list`, `list-subsys`, `list-ns`,
      `list-ctrl`, `id-ctrl`, `id-ns`, `ns-descs`, `smart-log`, `error-log`,
      `fw-log`, `telemetry-log`, `effects-log`, `endurance-log`,
      `sanitize-log`, `self-test-log`, `supported-log-pages`, `get-log`,
      `device-self-test`) and clears the ambient set before `execve` for
      everything else. `nvme format`, `nvme sanitize`, `nvme fw-commit`,
      `nvme help` and the vendor plugins still run, but with no capability, so
      they need `sudo` again. The vendor plugins are the reason: they
      interpolate the caller's `--dir-name` into a shell command string passed
      to `system()`
      (`plugins/solidigm/solidigm-internal-logs.c:989`,
      `plugins/wdc/wdc-nvme.c:4218`, `plugins/micron/micron-nvme.c:249`), which
      is metacharacter injection that no pinned `PATH` can bound.
  - effect on users outside `disk`:
    - none. The wrapper files are `root:disk 0510`, so a non-member cannot
      execute `/run/wrappers/bin/{smartctl,nvme,hdparm}`, but the app modules
      keep the packages in `environment.systemPackages` and PATH lookup (bash,
      zsh, `execvp`) skips an entry that fails `access(X_OK)` and keeps
      searching. A bare `smartctl` therefore falls through to the `0555`
      `/run/current-system/sw/bin/smartctl` and fails at the ioctl exactly as
      it did before the wrappers existed.
- Self-encrypting drive management:
  - `sedutil-cli ...`
  - mechanism:
    - `security.wrappers` with `CAP_SYS_ADMIN` plus `CAP_SYS_RAWIO`
    - available to users in the `disk` group
  - why group membership alone is not enough:
    - `blk_verify_command()` rejects the SECURITY PROTOCOL IN/OUT and ATA
      PASS-THROUGH CDBs that `SG_IO` carries without `CAP_SYS_RAWIO`, and that
      is the only path Opal traffic takes to SATA drives: the Linux backend
      leaves `PerformATACommand_via_HD` unimplemented, so no `HDIO_*` ioctl is
      involved.
    - `nvme_cmd_allowed()` rejects the NVMe security send/receive admin
      passthrough (`NVME_IOCTL_ADMIN_CMD`) without `CAP_SYS_ADMIN`.
  - device nodes:
    - `sedutil-cli` scans `/dev` by device major and keeps only whole-disk
      block nodes (SCSI 8, 65-71, 128-135, and NVMe 259), so `root:disk 0660`
      block nodes are all it needs. The NVMe controller char rule in
      `modules/hosts/common/storage-diagnostics.nix` is not on its path.
  - kernel prerequisite:
    - SATA drives additionally need `libata.allow_tpm=1`, documented in
      `docs/sedutil-cli.8` upstream, because libata otherwise refuses ATA
      TRUSTED SEND/RECEIVE. `modules/hosts/common/storage-diagnostics.nix` sets
      it in `boot.kernelParams`, so it takes effect on the next reboot rather
      than at switch time. NVMe drives do not need it.
  - limitation:
    - the wrapper covers the whole binary, so `--initialSetup`,
      `--setSIDPassword`, `--revertTPer`, and
      `--yesIreallywanttoERASEALLmydatausingthePSID` are passwordless for
      `disk` members too. The last two erase the drive, and a mistyped Opal
      password locks data that `disk` membership cannot recover, so this is a
      wider failure mode than the raw writes membership already permitted.
    - the wrapper source pins `PATH`, because a `popen()` helper is linked into
      `sedutil-cli` and `popen()` execs `/bin/sh -c`. `PATH` is absent from
      glibc's `unsecvars.h`, so the capability wrapper forwards the caller's
      value and the ambient capabilities would survive into whatever the shell
      resolved.
  - effect on users outside `disk`:
    - the same as the wrappers above. The wrapper file is `root:disk 0510`, so
      PATH lookup skips it and a bare `sedutil-cli` falls through to the
      `environment.systemPackages` copy, which fails at the ioctl.
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
    - the `tcpdump` wrapper source is an argv filter that refuses `-z`.
      `tcpdump.c:3173` runs the postrotate command through `execlp()`, and the
      wrapper's ambient `CAP_NET_RAW` and `CAP_NET_ADMIN` land in that child.
      The filter rejects `-z` in any getopt form (`-z cmd`, `-nz cmd`,
      `-zcmd`, and after an operand, since glibc `getopt_long` permutes).
      Compress rotated files as a separate step, or reach the unwrapped
      `/run/current-system/sw/bin/tcpdump` and accept that it has no
      capabilities.
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
      The common host baseline disables the optional wheel systemd
      unit-management rule.
  - `nix eval --json .#nixosConfigurations.$(hostname).config.security.sudo-rs.extraRules | jq`
  - `getcap /run/wrappers/bin/smartctl /run/wrappers/bin/nvme /run/wrappers/bin/sedutil-cli`
    - add `/run/wrappers/bin/hdparm` where the hdparm app module is enabled.
  - `ls -l /dev/nvme0 /dev/ng0n1 /dev/nvme0n1`
    - all three should be group `disk` with mode `0660`.
  - `systemctl status nvme-char-device-permissions`
    - should be `active (exited)`. It retriggers the `nvme` and `nvme-generic`
      subsystems whenever a switch changes the udev rules, so the node
      ownership above does not wait for a reboot.
  - `smartctl -a /dev/nvme0n1`, `nvme smart-log /dev/nvme0`
    - each should print device data instead of `Permission denied` or
      `Operation not permitted`.
    - `hdparm -I /dev/sda` applies only where the hdparm app module is enabled.
  - `sedutil-cli --scan`
    - should list whole-disk block nodes instead of reporting no access. A SATA
      drive reports Opal support only once `libata.allow_tpm=1` is set, which
      no module in this repo does; check
      `cat /sys/module/libata/parameters/allow_tpm` before treating a `No`
      there as a drive capability result.
  - `strings "$(nix eval --raw .#nixosConfigurations.$(hostname).config.security.wrappers.sedutil-cli.source)" | grep '^PATH='`
    - the wrapper source is a compiled `makeBinaryWrapper` binary that pins
      `PATH` to a store path. An empty result means the pin was lost and the
      ambient capabilities are reachable through a caller-controlled `PATH`.
  - `nvme sanitize-log /dev/nvme0; nvme get-feature /dev/nvme0 -f 4`
    - the first is allowlisted and should print log data; the second is not, so
      it should report `Permission denied`. Both succeeding means the argv
      filter was lost from `security.wrappers.nvme.source`.
  - `tcpdump -c 1 -C 1 -w /tmp/cap -z /bin/true`
    - should exit non-zero with `-z is refused by the capability wrapper`.
      A started capture means the argv filter was lost from
      `security.wrappers.tcpdump.source`.
