# sbx

`sbx` runs disposable VMs on the owner's `qemu:///session` for unknown binaries, untrusted repositories, and screenshots of a guest display.
Agents reach it as a plain command; it needs no group, no polkit prompt, and no access to `qemu:///system`.
The app module is `modules/apps/sbx/nixos.nix`; its ceilings come from the host's `sbx` entry in `modules/hosts/<host>/policy.nix`.

## Trust model

Every sandbox is an untrusted guest.

- It has no network interface; control runs over SSH on vsock and the qemu-ga channel.
- It has no vdagent channel, no display socket, and no shared folder.
- `sbx` accepts no domain XML, no host disk path, and no value above a ceiling.
- Host vsock listeners are reachable from a guest, so `create` refuses while one listens outside `vsockAllowlist`.
- Agents run as the owner, so the ceilings bind well-behaved callers only.

## Verbs

Every verb takes `--json`; a failure then prints `{"error": {"code", "message"}}` and exits non-zero.

| Verb                             | Effect                                      |
| -------------------------------- | ------------------------------------------- |
| `create <base>`                  | start a sandbox, wait for SSH               |
| `run <base> -- CMD`              | create, copy in, run, copy out, destroy     |
| `exec <name> -- CMD`             | run over SSH; `--agent` uses qemu-ga        |
| `cp <src> <dst>`                 | scp over vsock; one side is `<name>:<path>` |
| `destroy <name>`                 | stop, undefine, delete the run directory    |
| `list`, `info <name>`            | state, CID, TTL left, caller session        |
| `screenshot <name>`              | display to PNG; `--ocr` adds text           |
| `gc`                             | remove expired and orphaned sandboxes       |
| `base list`, `base build <base>` | show or build Nix bases                     |

`create` and `run` take `--name`, `--mem`, `--cpus`, and `--ttl`.
`destroy --mine` and `list --mine` act on sandboxes started from the caller's Claude Code session or Codex thread.

```sh
sbx base build nixos
sbx run nixos --in ./repo --out /root/repo/result.txt --to "$TMPDIR" -- make -C repo test
sbx create nixos --name probe --ttl 30m
sbx exec probe -- uname -a
sbx cp probe:/var/log/build.log
sbx destroy probe
```

## Copies

- A host source must sit under the caller's git checkout, `~/trees`, or `$TMPDIR`, and no symlink inside it may leave those roots.
- A copy out without a destination lands in the sandbox's `xfer` directory, which `info` prints.
- A copy out to a host path needs that path under the same roots.
- `run --out` needs `--to`, since `destroy` deletes the run directory.

## Bases

A base is a Nix-built disk image from `legacyPackages.x86_64-linux.workloads.sbx-<base>` in `modules/apps/sbx/bases.nix`.
`sbx base build` builds it from the `flake` option, or `--flake`, with an out-link under `~/.local/share/sbx/bases/` as its GC root.
No host closure references a base.
Each sandbox gets a qcow2 overlay on the base, its own GC root to the base, and a fresh ed25519 key.
The key reaches the guest as the `ssh.authorized_keys.root` systemd credential over fw_cfg.

## Resources

The session daemon runs as the user unit `sbx-libvirt.service` in `sbx.slice`, so QEMU and its helpers share the slice's memory and CPU limits.
`sbx` starts the unit before it connects and never lets libvirt autospawn a daemon.
`create` refuses when the daemon runs outside the slice, when the running count or their declared memory would pass a ceiling, when the state directory passes its disk cap, or when its filesystem falls below the free-space floor.
The TTL counts wall-clock time, host sleep included.

## State

| Path                              | Content                          |
| --------------------------------- | -------------------------------- |
| `~/.local/share/sbx/<name>/`      | overlay, NVRAM, key, console log |
| `~/.local/share/sbx/<name>/xfer/` | copies out and screenshots       |
| `~/.local/share/sbx/bases/<base>` | base out-link                    |

`sbx-gc.timer` runs `sbx gc` on a schedule.
It removes sandboxes past their TTL, shut-off sandboxes without a managed save, domains without a run directory, and run directories without a domain.
Every verb logs to the journal under `SYSLOG_IDENTIFIER=sbx`.

## Verify

As the owner:

```sh
systemctl --user status sbx.slice sbx-libvirt.service sbx-gc.timer
sbx base list --json
sbx run nixos -- systemd-detect-virt
journalctl --user -t sbx -n 20
```

## create fails with daemon-outside-slice

Cause: another `qemu:///session` client, such as virt-manager, spawned `virtqemud` before `sbx` did.

```sh
cat "$XDG_RUNTIME_DIR/libvirt/virtqemud.pid"
systemctl --user status sbx-libvirt.service
```

Fix: close that client's session connection, stop the stray `virtqemud`, and rerun the command.

## create fails with vsock-listener

Cause: a host process listens on vsock, so a sandbox could reach it.

```sh
ss -l --vsock
```

Fix: stop the listener, or add its port to `vsockAllowlist` when every sandbox may reach it.

## create fails with boot-timeout

Cause: the guest did not answer qemu-ga or SSH on vsock in time; the error carries the console tail.

```sh
sbx base list
```

Fix: rebuild the base with `sbx base build <base>` and retry; a failure that repeats points at the base configuration.
