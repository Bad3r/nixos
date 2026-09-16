# Owner No-Sudo NVMe Subcommand Allowlist

Which `nvme` subcommands keep the storage capability the wrapper raises, and which clear it.
`modules/apps/nvme-cli.nix` enumerates the allowlist and is the authoritative list.
The wrapper mechanism and the `disk` group grant it builds on are on [owner-no-sudo-storage.md](owner-no-sudo-storage.md).

## What Keeps The Capability

The `nvme` wrapper is not whole-binary. Its source allowlists 47 subcommands.
Membership is limited to Identify (opcode 0x06, such as `id-ctrl`, `id-nvmset`,
`primary-ctrl-caps`, `list-secondary`), Get Log Page (opcode 0x02, such as
`smart-log`, `error-log`, `ana-log`, `lba-status-log`,
`rotational-media-info-log`), and Get Features (opcode 0x0A, which is
`get-feature` alone, carrying no `--save`, so the saved-value write path stays
behind `set-feature` and the verbatim `strcmp` does not match it).

Two exceptions are allowlisted because their state change is the diagnostic itself:

- `device-self-test`, whose options start or abort a drive self-test.
- `telemetry-log`, whose default `--host-generate=1` (`nvme.c:916`) sets the
  Create bit in the Telemetry Host-Initiated log's LSP so the controller
  captures fresh host-initiated telemetry in place of the capture it retained
  (`--host-generate=0` re-reads that capture; `--controller-init` reads the
  separate controller-initiated log, which the bit never touches), and whose
  `--data-area=4` sets the ETDAS bit of Host Behavior Support (feature 16h)
  through Set Features and clears it again after the read (libnvme
  `linux.c:124`).

The filter matches `argv[1]` only, so neither exception constrains options.
Host-initiated telemetry exists only because a host asked for it, and the
command that creates it copies it out in the same run, so no other consumer
waits on the retained copy.

Ten allowlisted log readers accept `--rae`; omitting it lets the controller
clear the associated asynchronous event, which is a property of the log pages
themselves and applies equally to the long-standing `smart-log` and `error-log`
grants, both of which pass `rae = false`.
`resv-notif-log` is allowlisted despite reading a queue whose oldest entry the
controller retires on read, because nothing on these hosts consumes NVMe
reservation notifications; revisit that if a namespace is ever shared with a
second host.

## What Clears The Capability

The filter clears the ambient set before `execve` for everything else.
`nvme format`, `nvme sanitize`, `nvme set-feature`, `nvme fw-commit`,
`nvme admin-passthru`, `nvme io-passthru`, and the vendor plugins still run, but
with no capability, so they need `sudo` again.

The vendor plugins are the reason the wrapper is an allowlist rather than a
denylist: they interpolate the caller's `--dir-name` into a shell command string
passed to `system()` (`plugins/solidigm/solidigm-internal-logs.c:989`,
`plugins/wdc/wdc-nvme.c:4218`, `plugins/micron/micron-nvme.c:249`), which is
metacharacter injection that no pinned `PATH` can bound.

Five subcommands that read data are excluded on purpose, because the read is not
free of state change:

- `changed-ns-list-log` and `changed-alloc-ns-list-log` are clear-on-read, so
  consuming the list can hide a namespace-change event from another reader.
- `persistent-event-log` takes an `--action` that establishes or releases a
  controller-side log context (`nvme.c:1685-1705`).
- `phy-rx-eom-log` can initiate a PHY receiver eye-opening measurement rather
  than only report one.
- raw `get-log` (`nvme.c:2390`) takes any `--log-id` with any `--lsp` below 128,
  so `--log-id persistent-event --lsp 1`, `--log-id changed-ns`, and
  `--log-id telemetry-host --lsp 1` reach every effect above under a name that
  none of the other exclusions matches.

## What Never Needed The Wrapper

`nvme_cmd_allowed()` exempts the `NS`, `CS_NS`, `NS_CS_INDEP`, `CTRL`, and
`CS_CTRL` CNS values, so `nvm-id-ctrl`, `nvm-id-ns`, and `cmdset-ind-id-ns`
already reach the drive unprivileged.
`get-ns-id` is a plain `NVME_IOCTL_ID` and needs a namespace node
(`/dev/nvme0n1`), not a controller node.
`nvme help` also runs on the cleared path without the storage capability; it may
still fail for an ordinary reason such as a missing manual page.

## Verification

- Commands:
  - `nvme sanitize-log /dev/nvme0; nvme get-log /dev/nvme0 --log-id 2 --log-len 512`
    - the first is allowlisted and should print log data; the second is raw
      `get-log`, one of the deliberate exclusions, so it should report
      `Permission denied`. Both succeeding means the argv filter was lost from
      `security.wrappers.nvme.source`.
