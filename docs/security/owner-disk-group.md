# Owner disk group privileges

The owner profile in `modules/meta/owner.nix` assigns the `disk` group; the wrappers come from `modules/hosts/common/storage-diagnostics.nix` and the app modules for each tool.

- access:
  - raw block devices (e.g. `/dev/sda`, `/dev/nvme0n1`).
  - NVMe controller and generic char devices (`/dev/nvme0`, `/dev/ng0n1`) via
    the shared udev rule in `modules/hosts/common/storage-diagnostics.nix`.
  - storage diagnostic wrappers with `CAP_SYS_ADMIN` / `CAP_SYS_RAWIO` for:
    - `smartctl`
    - `nvme`
    - `sedutil-cli`
    - `hdparm` (when the hdparm app module is enabled)
- security impact:
  - full read/write access to storage devices, bypassing filesystem permissions. Allows running tools like `fdisk` without sudo.
  - the `smartctl` wrapper is filtered. It retains capabilities only for
    audited reports, the documented `-v`/`--vendorattribute` display
    definitions and `-F`/`--firmwarebug` report workarounds, read-only settings
    and log queries (including bare `-n sleep`, `-n standby`, and `-n idle`
    power-mode checks), and the standard `offline`, `short`, `long`, and
    `conveyance` self-tests documented by the module. SMART configuration
    (`-s`, `-o`, `-S`, and `--set`), log resets or writes,
    selective/pending/force/captive/abort tests, and unknown forms clear the
    ambient set and need `sudo`.
  - the `hdparm` wrapper retains capabilities only for short-option clusters made from `-C`, `-g`, `-i`,
    `-I`, `-t`, and `-T`. Standalone input formatting such as `--Istdin` also
    takes the cleared-capability path, but reads and formats stdin only,
    opens no device, and needs neither storage capabilities nor `sudo`. ATA
    Security, DCO/HPA, raw-sector writes, TRIM, sanitize, firmware,
    device-setting, unknown, and parameter-bearing options clear the ambient
    set and need `sudo`.
    Raw block reads and writes remain available through `disk` membership,
    but that does not grant the separate ATA Security, DCO, or HPA control
    paths.
  - the `nvme` wrapper is not whole-binary. Its source allowlists the
    diagnostic subcommands that leave media and settings untouched (the log
    readers still clear the asynchronous event tied to the page they read)
    plus two whose state change is the
    diagnostic itself, `device-self-test`, whose options can start or abort
    a drive self-test, and `telemetry-log`, whose default run has the
    controller capture fresh host-initiated telemetry in place of the
    retained capture, and clears the ambient capability set before `execve`
    for everything else. `nvme format`, `nvme sanitize`, `nvme fw-commit`,
    raw `nvme get-log`, and the vendor plugins therefore run without
    `CAP_SYS_ADMIN` and need `sudo` again. `nvme help` also runs on the
    cleared path without the storage capability, although it may fail if
    the manual page is unavailable. See
    [docs/security/owner-no-sudo-operations.md](owner-no-sudo-operations.md)
    for the allowlist and the `system()` injection sites that motivate it.
  - for the sedutil 1.49.13 parser, the `sedutil-cli` wrapper is also
    filtered. It retains capabilities only for `--scan` and its JSON output
    forms, `--query` and its JSON output forms with one device,
    `--isValidSED <device>`, and `--printDefaultPassword <device>`. Opal
    password, locking-range, PBA, and revert actions clear the ambient set
    and need `sudo` again. `--printDefaultPassword` exposes the drive MSID
    and should be treated as credential material. The filter checks the first
    action and relies on sedutil's exact and maximum argument checks to reject
    later actions before dispatch; re-audit a custom package if that parser
    changes.
