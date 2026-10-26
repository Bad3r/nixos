# Commands in sbx sandboxes

`sbx exec` runs one command in a sandbox, and `sbx run` runs one in a sandbox of its own; the [sbx README](README.md) covers the other verbs.

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

`exec` exits in both output modes with:

- the guest status;
- 124 once the deadline passed;
- 128 plus the signal number when a signal ended the command;
- 255 for a transport error, which `transport_error` tells apart from a guest's own exit 255.

[Troubleshooting](troubleshooting.md#exec-reports-a-transport-error) covers transport errors.

## One-shot runs

`run` creates a sandbox, copies each `--in` into `/root/` (`C:\sbx\` on Windows), runs the command, copies each `--out` to `--to`, and destroys the sandbox.
`/root/` is readable only by root, so on Linux `run` refuses `--in` with a `--user` other than root.
`run --json` prints one document, and the MCP `run` tool returns the same:

| Field       | Meaning                                        |
| ----------- | ---------------------------------------------- |
| `sandbox`   | name, base, net, size, session, token, created |
| `phases`    | `ok`, `failed`, or `skipped` per phase         |
| `in`, `out` | each copy's `from` and `to`                    |
| `exec`      | the result above, or null                      |
| `cleanup`   | the `destroyed` names and an `error`           |
| `failure`   | the error that stopped `in` or `exec`          |

The phases are `create`, `in`, `exec`, `out`, and `cleanup`.

Before it boots or queues, `run` checks each `--in` and every `--out` target under `--to`, the base, the egress bridge, and the disk limits.
Two inputs with one name, an output path that names no file, two outputs with one target, and an existing target refuse there.
Each step checks its part again when it acts.

- A failed copy in skips `exec` and `out`; a failed `exec` or a transport error skips `out`.
- Each copy out runs on its own: a failed one carries `error` in place of `to`, and the others still publish.
- The sandbox is destroyed in every case, and a failed destroy lands in `cleanup.error` beside the command's result.
- A failed create reports its own error, such as `over-limit`, since nothing ran.

A run exits with the guest status only when every phase succeeded.
Otherwise it fails with `run-incomplete` and exits 1; the error object adds the first failed `phase` and the whole document under `run`, so `run.exec` keeps the command's result.
Without `--json`, stderr gets one line per failed copy out and for a failed cleanup.
