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
- The listener check sees the initial network namespace only; the module sets `net.vsock.child_ns_mode` to `local` so later namespaces keep their vsock sockets to themselves.
  A namespace created before that sysctl applies at boot stays global and unseen.
- The guest sees no nested virtualization and no VMware backdoor port.
- An expired sandbox refuses `exec`, `cp`, and `screenshot` until `gc` removes it.
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
| `sleep <phase>`                  | host sleep hook only, not for agents        |

`create` and `run` take `--name`, `--mem`, `--cpus`, and `--ttl`.
`exec` and `run` exit with the guest command's status in both output modes, or 124 after `--timeout`, which also stops the command inside the guest.
`destroy --mine` and `list --mine` act on sandboxes started from the caller's Claude Code session or Codex thread.
[sleep.md](sleep.md) covers `sleep` and what host suspend and hibernation do to sandboxes.

```sh
sbx base build nixos
sbx run nixos --in ./repo --out /root/repo/result.txt --to "$TMPDIR" -- make -C repo test
sbx create nixos --name probe --ttl 30m
sbx exec probe -- uname -a
sbx cp probe:/var/log/build.log
sbx destroy probe
```

## Copies

- A host source must sit under the caller's git checkout, `~/trees`, or `$TMPDIR`.
  A symlink inside it may point only to a file within those roots, never to a directory.
- A copy out names a file or directory, never `.`, `..`, or `/`.
  It is staged in the sandbox's `xfer` directory, which `info` prints, and loses execute, setuid, and setgid bits.
- Without a destination the copy stays in `xfer`; a host destination must sit under the same roots.
- A copy out never overwrites: its target must not exist.
- A copy out stops once it passes the room left under the disk cap and the free-space floor.
- `run --out` and `run --to` go together, since `destroy` deletes the run directory.

## Bases

A base is a Nix-built disk image from `legacyPackages.x86_64-linux.workloads.sbx-<base>` in `modules/apps/sbx/bases.nix`.
`sbx base build` builds it from the flake the `flake` option names, with an out-link under `~/.local/share/sbx/bases/` as its GC root.
No host closure references a base.
Each sandbox gets a qcow2 overlay on the base, its own GC root to the base, and a fresh ed25519 key.
The key reaches the guest as the `ssh.authorized_keys.root` systemd credential over fw_cfg.

## Resources

The session daemon runs as the user unit `sbx-libvirt.service` in `sbx.slice`, so QEMU and its helpers share the slice's memory limit.
The declared-memory ceiling sits below the slice limit, which leaves room for QEMU's own overhead.
The user manager has no cpuset controller, so each domain pins its vCPUs and emulator threads to the policy's CPUs itself.
`sbx` starts the unit before it connects and never lets libvirt autospawn a daemon.
`create` refuses when:

- the daemon runs outside the slice;
- the running count or the declared memory would pass a ceiling;
- the state directory's usage plus a full disk for every running sandbox and the new one would pass the disk cap;
- its filesystem falls below the free-space floor.

The TTL counts wall-clock time, host sleep included.

## State

| Path                              | Content                          |
| --------------------------------- | -------------------------------- |
| `~/.local/share/sbx/<name>/`      | overlay, NVRAM, key, console log |
| `~/.local/share/sbx/<name>/xfer/` | copies out and screenshots       |
| `~/.local/share/sbx/bases/<base>` | base out-link                    |

`sbx-gc.timer` runs `sbx gc` on a schedule.
It removes sandboxes past their TTL, shut-off sandboxes without a managed save, domains without a run directory, and run directories without a domain.
`create`, `exec`, `cp`, `screenshot`, `destroy`, `gc`, `base build`, and every refusal log to the journal under `SYSLOG_IDENTIFIER=sbx`.

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
