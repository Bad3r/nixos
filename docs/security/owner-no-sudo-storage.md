# Owner No-Sudo Storage Diagnostics

Storage inspection and health reporting available to the owner user without entering a sudo password.
The NVMe subcommand allowlist has its own page, and self-encrypting drive management has another.

Scope:

- storage capability wrappers:
  - `modules/apps/smartmontools.nix`
  - `modules/apps/nvme-cli.nix`
  - `modules/apps/hdparm.nix`
- shared NVMe char-device udev rule and its retrigger unit:
  - `modules/hosts/common/storage-diagnostics.nix`

## Commands That Do Not Require `sudo`

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
      Each mixed read/write storage command is fronted by a compiled argv
      filter. The `smartctl` filter scans the complete argument vector because
      its `getopt_long` parser permutes options around device operands. A
      filter is never a shell script: a capability wrapper is not setuid, so
      `euid == uid`, bash does not enter privileged mode, and `BASH_ENV` is
      absent from glibc's `unsecvars.h`.
  - limitation:
    - the `smartctl` wrapper is filtered: it retains capabilities only for
      audited reports, the documented `-v`/`--vendorattribute` display
      definitions and `-F`/`--firmwarebug` report workarounds, read-only settings
      and log queries (including bare `-n sleep`, `-n standby`, and `-n idle`
      power-mode checks), and the standard `offline`, `short`, `long`, and
      `conveyance` self-tests documented by the module. SMART configuration
      (`-s`, `-o`, `-S`, and `--set`), log resets or writes,
      selective/pending/force/captive/abort tests, and unknown forms clear the
      ambient set and need `sudo` again. The filter fails closed when a package
      update adds an unrecognized option or argument form.
    - the `hdparm` wrapper is filtered: it retains capabilities only for
      short-option clusters made from `-C`, `-g`, `-i`, `-I`, `-t`, and `-T`.
      Standalone input formatting such as `--Istdin` also takes the
      cleared-capability path, but reads and formats stdin only, opens no
      device, and needs neither storage capabilities nor `sudo`. ATA Security,
      DCO/HPA, raw-sector writes, TRIM, sanitize, firmware, device-setting,
      unknown, and parameter-bearing options clear the ambient set and need
      `sudo` again. `-t` and `-T` are non-media-mutating timing
      diagnostics, but may flush or synchronize caches. The existing `disk`
      membership still permits raw block reads and writes; that does not grant
      the separate ATA Security, DCO, or HPA control paths.
    - the `nvme` wrapper is not whole-binary; its allowlist and exclusions are
      on [owner-no-sudo-nvme.md](owner-no-sudo-nvme.md).
  - effect on users outside `disk`:
    - none. The wrapper files are `root:disk 0510`, so a non-member cannot
      execute `/run/wrappers/bin/{smartctl,nvme,hdparm}`, but the app modules
      keep the packages in `environment.systemPackages` and PATH lookup (bash,
      zsh, `execvp`) skips an entry that fails `access(X_OK)` and keeps
      searching. A bare `smartctl` therefore falls through to the `0555`
      `/run/current-system/sw/bin/smartctl` and fails at the ioctl exactly as
      it did before the wrappers existed.

## Related

- Grants that need no capability wrapper:
  - [owner-no-sudo-operations.md](owner-no-sudo-operations.md)
- Self-encrypting drive management:
  - [owner-no-sudo-sed.md](owner-no-sudo-sed.md)

## Verification

- Commands:
  - `getcap /run/wrappers/bin/smartctl /run/wrappers/bin/nvme`
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
  - `strings "$(nix eval --raw .#nixosConfigurations.$(hostname).config.security.wrappers.smartctl.source)" | grep -F '/bin/smartctl'`
    - the wrapper source is a compiled argv filter whose target is the
      smartmontools binary. An empty result means the capability-bearing
      wrapper is not bound to the filtered target.
  - `strings "$(nix eval --raw .#nixosConfigurations.$(hostname).config.security.wrappers.hdparm.source)" | grep -F '/bin/hdparm'`
    - the wrapper source is a compiled argv filter whose target is the hdparm
      binary. An empty result means the filter is not bound to the package
      binary.
  - `strace -f -e trace=prctl /run/wrappers/bin/smartctl -a /dev/null`,
    `strace -f -e trace=prctl /run/wrappers/bin/smartctl -v '9,raw24(raw8)' -a /dev/null`,
    and `strace -f -e trace=prctl /run/wrappers/bin/smartctl --firmwarebug=swapid -a /dev/null`
    - the report and audited report-modifier forms should execute without
      `PR_CAP_AMBIENT_CLEAR_ALL`.
  - `strace -f -e trace=prctl /run/wrappers/bin/smartctl -v 9,bad -a /dev/null`
    and `strace -f -e trace=prctl /run/wrappers/bin/smartctl -s off /dev/null`
    - both forms should show `PR_CAP_AMBIENT_CLEAR_ALL` before execution. The
      target device may still reject a diagnostic after the filter test.
  - `strace -f -e trace=prctl /run/wrappers/bin/hdparm -V`
    - should show `PR_CAP_AMBIENT_CLEAR_ALL` before the non-allowlisted version
      action executes. A missing call means the filter is not clearing
      capabilities for state-changing and unknown options.
