# Commands in sbx sandboxes

`sbx exec` and `sbx run` run one command in a sandbox; the [sbx README](README.md) covers the other verbs.

## Transports

- `exec --json`, `run --json`, the MCP `exec` and `run` tools, and every Windows sandbox capture the command through qemu-ga `guest-exec`.
- A plain `exec` or `run` on a Linux sandbox attaches the caller's terminal over SSH on vsock; `cp` copies over the same SSH.
- qemu-ga returns the output only once the command exits, so a captured command shows nothing until it ends.

## Timeouts

`--timeout 10m` sets a deadline on the host's monotonic clock, which stands still while the host sleeps.

- Past the deadline, a captured Linux command's process group gets SIGTERM, then SIGKILL 5 s later, and the output it printed is kept.
- A captured Windows command's process tree is stopped with `taskkill /T /F` instead.
- An attached command runs under coreutils `timeout` in the guest, with the same grace before SIGKILL.
- `timed_out` is true only once the deadline passed: a command that exits 124 on its own reports `exit_code: 124` and `timed_out: false`.

## Results

`--json` prints one document, and the MCP tools return the same:

| Field              | Meaning                                  |
| ------------------ | ---------------------------------------- |
| `exit_code`        | the guest status, or null                |
| `signal`           | the signal that ended it, such as `KILL` |
| `timed_out`        | the host deadline passed                 |
| `killed`           | the signals of `sbx` ended the command   |
| `transport_error`  | qemu-ga or SSH failed mid-command        |
| `duration_s`       | host seconds from start to result        |
| `stdout`, `stderr` | output up to the output limit            |
| `truncated`        | output past the limit was dropped        |

Both output modes exit with:

- the guest status;
- 124 once the deadline passed;
- 128 plus the signal number when a signal ended the command;
- 255 for a transport error, which `transport_error` tells apart from a guest's own exit 255.

[Troubleshooting](troubleshooting.md#exec-reports-a-transport-error) covers transport errors.
