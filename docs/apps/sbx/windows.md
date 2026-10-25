# sbx Windows bases

A Windows base clones a declared Windows guest's [golden copy](../libvirt/windows.md#take-a-golden-copy) into disposable sandboxes on the owner's `qemu:///session`.
Every present guest of kind `windows` gets a base of its own name through the `windowsBases` option in `modules/apps/sbx/nixos.nix`.
The sandbox code lives in `packages/sbx/sbx/windows.py`, the export in `packages/sbx/sbx/export.py`.

## Export

The golden copy is readable by root only, so `sbx-base@<name>.service` copies it for the owner.

- Root opens the golden disk, NVRAM, and TPM state read-only and hands the open files to a process running as the owner.
- That process writes them under `~/.local/share/sbx/bases/<name>/<time>/`, owner-only and read-only; root never writes below the home directory.
- Each export is a new directory named by its UTC time, and an unchanged golden copy is not exported again.
- The export refuses to leave less than the sbx free-space floor on the home filesystem.
- Exports stay outside the sandbox disk cap; `sbx gc` removes an export that is neither the newest nor under a sandbox.

## Sandboxes

`sbx create <name>` clones the newest export.

- The overlay sits on the export's disk, and the sandbox gets its own copies of the NVRAM and TPM state.
- The firmware is the libvirt app's Microsoft-enrolled OVMF, whose keys the golden NVRAM holds, so Secure Boot and the TPM stay as Windows was installed.
- swtpm, which parses the guest's TPM commands, runs in a user and network namespace of its own, as QEMU does.
- A sandbox has no network, so clones sharing the golden copy's SIDs, activation, and account never meet one another.
- It has no vsock device and no SSH: every command and file goes through the guest agent, which runs as SYSTEM.
- Its virtual disk is the guest's, larger than the sandbox disk cap.
  `create` reserves `sandbox.maxFile` per Windows sandbox instead, the file size limit of `sbx-libvirt.service`.
  A write past that limit fails, and the sandbox pauses with an I/O error until it is destroyed or its TTL ends.
- `sandbox.windowsMemory` sets the default memory.

## Commands and copies

- `exec` runs the command as given, without a shell; a Windows shell is a command of its own, such as `cmd.exe /c dir C:\`.
- Paths in the guest are absolute, such as `C:\Users\Public\out.txt`.
- `--timeout` ends the command's whole process tree with `taskkill`; a failed kill is reported in stderr.
- A copy in lands inside the named guest directory, which is created if missing; `run --in` copies into `C:\sbx\`.
- Copies travel as archives through the guest's `tar.exe`.
  A copy out refuses links and special files, and the copy roots, budget, and no-overwrite rules of the [README](README.md#copies) apply.

```sh
sbx run win11 --in "$TMPDIR/setup.exe" -- 'C:\sbx\setup.exe' /S
sbx create win11 --name probe --ttl 1h
sbx exec probe -- cmd.exe /c ver
sbx cp 'probe:C:\Users\Public\log' "$TMPDIR"
sbx destroy probe
```

## Export a Windows base

Precondition: the guest's golden copy exists, as in [Take a golden copy](../libvirt/windows.md#take-a-golden-copy).

1. From a session on the host, start the export as the owner and authenticate at the prompt:

   ```sh
   systemctl start sbx-base@<name>.service
   ```

2. Read its log:

   ```sh
   journalctl -u sbx-base@<name>.service -b
   ```

Verification: `sbx base list` reports the base with `built` true and the export the log names as its path.

## Remove a Windows base

Precondition: no sandbox uses the base.

1. Delete its exports as the owner:

   ```sh
   rm -r ~/.local/share/sbx/bases/<name>
   ```

Verification: `sbx base list` reports the base with `built` false.

## create fails with base-missing

Cause: the base has no export yet.

```sh
sbx base list --json
```

Fix: export it as in [Export a Windows base](#export-a-windows-base).

## sbx-base fails

Cause: the guest has no golden copy, or the export would pass the free-space floor.

```sh
journalctl -u sbx-base@<name>.service -b -p err
```

Fix: take the golden copy, or free space and run `sbx gc` to drop superseded exports.

## A Windows sandbox is paused

Cause: its overlay reached the file size limit of `sbx-libvirt.service`, and `domstate --reason` reports an I/O error.

```sh
virsh -c qemu:///session domstate --reason sbx-<name>
ls -l ~/.local/share/sbx/<name>/disk.qcow2
```

Fix: destroy the sandbox; work that writes more needs a larger `sandbox.maxFile` and disk cap.
