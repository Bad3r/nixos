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
    - the `nvme` wrapper is not whole-binary. Its source allowlists 47
      subcommands, enumerated in `modules/apps/nvme-cli.nix`, which is the
      authoritative list. Membership is limited to Identify (opcode 0x06, such
      as `id-ctrl`, `id-nvmset`, `primary-ctrl-caps`, `list-secondary`), Get
      Log Page (opcode 0x02, such as `smart-log`, `error-log`, `ana-log`,
      `lba-status-log`, `rotational-media-info-log`), Get Features (opcode
      0x0A, which is `get-feature` alone, carrying no `--save`, so the
      saved-value write path stays behind `set-feature` and the verbatim
      `strcmp` does not match it), plus two exceptions whose state change is
      the diagnostic itself: `device-self-test`, whose options start or abort
      a drive self-test, and `telemetry-log`, whose default
      `--host-generate=1` (`nvme.c:916`) sets the Create bit in the Telemetry
      Host-Initiated log's LSP so the controller captures fresh host-initiated
      telemetry in place of the capture it retained (`--host-generate=0`
      re-reads that capture; `--controller-init` reads the separate
      controller-initiated log, which the bit never touches), and whose
      `--data-area=4` sets the ETDAS bit of Host Behavior Support (feature
      16h) through Set Features and clears it again after the read (libnvme
      `linux.c:124`). The filter matches `argv[1]` only, so neither exception
      constrains options. Host-initiated telemetry exists only because a host
      asked for it, and the command that creates it copies it out in the same
      run, so no other consumer waits on the retained copy.
      It clears the ambient set before `execve` for everything else.
      `nvme format`, `nvme sanitize`, `nvme set-feature`, `nvme fw-commit`,
      `nvme admin-passthru`, `nvme io-passthru`, and the vendor plugins still
      run, but with no capability, so they need `sudo` again.
      Five subcommands that read data are excluded on purpose, because the
      read is not free of state change: `changed-ns-list-log` and
      `changed-alloc-ns-list-log` are clear-on-read, so consuming the list can
      hide a namespace-change event from another reader; `persistent-event-log`
      takes an `--action` that establishes or releases a controller-side log
      context (`nvme.c:1685-1705`); `phy-rx-eom-log` can initiate a PHY
      receiver eye-opening measurement rather than only report one; and raw
      `get-log` (`nvme.c:2390`) takes any `--log-id` with any `--lsp` below
      128, so `--log-id persistent-event --lsp 1`, `--log-id changed-ns`, and
      `--log-id telemetry-host --lsp 1` reach every effect above under a
      name that none of the other exclusions matches.
      Ten allowlisted log readers accept `--rae`; omitting it lets the
      controller clear the associated asynchronous event, which is a property
      of the log pages themselves and applies equally to the long-standing
      `smart-log` and `error-log` grants, both of which pass `rae = false`.
      `resv-notif-log` is allowlisted despite reading a queue whose oldest
      entry the controller retires on read, because nothing on these hosts
      consumes NVMe reservation notifications; revisit that if a namespace is
      ever shared with a second host.
      Some Identify subcommands never needed the wrapper: `nvme_cmd_allowed()`
      exempts the `NS`, `CS_NS`, `NS_CS_INDEP`, `CTRL`, and `CS_CTRL` CNS
      values, so `nvm-id-ctrl`, `nvm-id-ns`, and `cmdset-ind-id-ns` already
      reach the drive unprivileged. `get-ns-id` is a plain `NVME_IOCTL_ID` and
      needs a namespace node (`/dev/nvme0n1`), not a controller node.
      `nvme help` also runs on the cleared path without the storage capability;
      it may still fail for an ordinary reason such as a missing manual page.
      The vendor plugins are the reason: they
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
      it to `boot.kernelParams` while `programs.sedutil.extended.enable` is
      true, so it takes effect on the next reboot rather than at switch time.
      NVMe drives do not need it.
  - limitation:
    - for the sedutil 1.49.13 parser, the compiled `sedutil-cli` wrapper keeps
      capabilities only for `--scan` and its JSON output forms, `--query` and
      its JSON output forms with one device, `--isValidSED <device>`, and
      `--printDefaultPassword <device>`. State-changing actions such as
      `--initialSetup`, `--setSIDPassword`, `--setLockingRange`,
      `--loadPBAimage`, `--revertTPer`, and
      `--yesIreallywanttoERASEALLmydatausingthePSID` clear the ambient set and
      need `sudo` again. The last two erase the drive. `--printDefaultPassword`
      is intentionally allowed and exposes the drive MSID, so treat its output
      as credential material. The filter checks the first action and relies on
      sedutil's exact and maximum argument checks to reject later actions before
      dispatch; re-audit a custom package if that parser changes.
    - `sedutil-cli` links a `popen()` helper that execs `/bin/sh -c`. Its target
      pins `PATH` to a store path as defense in depth, and the filter clears
      ambient capabilities before every non-allowlisted first action, so a
      helper on that path cannot inherit the storage capabilities.
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
      `modules/hosts/common/storage-diagnostics.nix` adds it while sedutil is
      enabled, for the next reboot after a switch; check
      `cat /sys/module/libata/parameters/allow_tpm` before treating a `No`
      there as a drive capability result.
  - `strings "$(nix eval --raw .#nixosConfigurations.$(hostname).config.security.wrappers.sedutil-cli.source)" | grep -F 'sedutil-cli-pinned-path/bin/sedutil-cli'`
    - the wrapper source is a compiled argv filter whose target is the
      `makeBinaryWrapper` output with a fixed `PATH`. An empty result means the
      filter is not bound to the pinned target.
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
  - `strace -f -e trace=prctl /run/wrappers/bin/sedutil-cli --version`
    - should show `PR_CAP_AMBIENT_CLEAR_ALL` before the unprivileged `--version`
      action executes. A missing call means the filter is not clearing
      capabilities for non-allowlisted actions.
  - `nvme sanitize-log /dev/nvme0; nvme get-log /dev/nvme0 --log-id 2 --log-len 512`
    - the first is allowlisted and should print log data; the second is raw
      `get-log`, one of the deliberate exclusions, so it should report
      `Permission denied`. Both succeeding means the argv filter was lost from
      `security.wrappers.nvme.source`.
  - `tcpdump -c 1 -C 1 -w /tmp/cap -z /bin/true` as a non-root caller
    - should exit non-zero with `-z is refused by the capability wrapper`.
      A started capture means the argv filter was lost from
      `security.wrappers.tcpdump.source`.
  - `sudo tcpdump -c 1 -C 1 -w /tmp/cap -z /bin/true` as root, with a valid
    capture target
    - should not emit the wrapper refusal. A later capture or tcpdump error is
      from the real root execution path.
