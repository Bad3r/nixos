# Owner No-Sudo Self-Encrypting Drive Management

Opal drive queries available to the owner user without entering a sudo password.
The `disk` group grant these wrappers build on is on [owner-no-sudo-storage.md](owner-no-sudo-storage.md).

Scope:

- capability wrapper:
  - `modules/apps/sedutil.nix`
- kernel parameter:
  - `modules/hosts/common/storage-diagnostics.nix`

## Commands That Do Not Require `sudo`

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
    - SATA drives additionally need `libata.allow_tpm=1`, documented in the
      upstream sedutil manual page, because libata otherwise refuses ATA
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
    - the same as the storage wrappers. The wrapper file is `root:disk 0510`, so
      PATH lookup skips it and a bare `sedutil-cli` falls through to the
      `environment.systemPackages` copy, which fails at the ioctl.

## Verification

- Commands:
  - `getcap /run/wrappers/bin/sedutil-cli`
  - `sedutil-cli --scan`
    - should list whole-disk block nodes instead of reporting no access. A SATA
      drive reports Opal support only once `libata.allow_tpm=1` is set, which
      `modules/hosts/common/storage-diagnostics.nix` adds while sedutil is
      enabled, for the next reboot after a switch; check
      `cat /sys/module/libata/parameters/allow_tpm` before treating a `No`
      there as a drive capability result.
  - `strings "$(nix eval --raw .#nixosConfigurations.$(hostname).config.security.wrappers.sedutil-cli.source)" | grep -F 'sedutil-cli-pinned-path/bin/sedutil-cli'`
    - the wrapper source is a compiled argv filter whose target is the
      `makeBinaryWrapper` output with a fixed `PATH`. An empty result means the
      filter is not bound to the pinned target.
  - `strace -f -e trace=prctl /run/wrappers/bin/sedutil-cli --version`
    - should show `PR_CAP_AMBIENT_CLEAR_ALL` before the unprivileged `--version`
      action executes. A missing call means the filter is not clearing
      capabilities for non-allowlisted actions.

External source: [sedutil](https://github.com/Drive-Trust-Alliance/sedutil)
