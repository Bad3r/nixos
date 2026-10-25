# Commands in sbx sandboxes

`sbx exec` and `sbx run` run one command in a sandbox; the [sbx README](README.md) covers the other verbs.

## Transports

- `exec --json`, `run --json`, the MCP `exec` and `run` tools, and every Windows sandbox capture the command through qemu-ga `guest-exec`.
- A plain `exec` or `run` on a Linux sandbox attaches the caller's terminal over SSH on vsock; `cp` copies over the same SSH.
- qemu-ga returns the output only once the command exits, so a captured command shows nothing until it ends.

## Context

Both transports start the command through one launcher, so they agree on its context.

- It runs as root in `/root` with `HOME=/root`, after the guest's `/etc/profile` set `PATH` and the session variables.
- `--user NAME` runs it as that guest user, with `HOME` and the default directory taken from the user's passwd entry.
- `--cwd PATH` sets an absolute directory, and `--env NAME=VALUE`, repeatable, exports a variable after the profile.
- `--stdin FILE` feeds a file under the copy roots to the command, and `--stdin -` feeds what `sbx` reads; either stops at 1 MiB, and larger input belongs in `cp`.
- A launcher failure, such as an unknown user or a missing directory, exits 125 with a `sbx:` line or the shell's error on stderr.
- Windows sandboxes refuse `--cwd`, `--env`, and `--user` with `unsupported`: qemu-ga runs the program as SYSTEM without a shell.

The MCP tools take the same as `cwd`, `env` (an object), `user`, and `stdin` text or `stdin_base64` bytes.

## Timeouts

`--timeout 10m` sets a deadline on the host's monotonic clock, which stands still while the host sleeps.
`--timeout 0s` is refused with `invalid-argument`; leave the flag out for no deadline.

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
| `stdout_lossy`     | invalid UTF-8 in stdout was replaced     |
| `stderr_lossy`     | the same for stderr                      |
| `truncated`        | output past the limit was dropped        |

`--output-encoding base64`, `encoding` in MCP, returns `stdout` and `stderr` as base64 of the raw bytes, and the `*_lossy` fields stay false.

Both output modes exit with:

- the guest status;
- 124 once the deadline passed;
- 128 plus the signal number when a signal ended the command;
- 255 for a transport error, which `transport_error` tells apart from a guest's own exit 255.

[Troubleshooting](troubleshooting.md#exec-reports-a-transport-error) covers transport errors.
