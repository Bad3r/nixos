# sbx

`sbx` runs disposable VMs on the owner's `qemu:///session` for unknown binaries, untrusted repositories, and screenshots of a guest display.
Agents reach it as a plain command; it needs no group, no polkit prompt, and no access to `qemu:///system`.
The app module is `modules/apps/sbx/nixos.nix`; its ceilings come from the host's `sbx` entry in `modules/hosts/<host>/policy.nix`.

## Trust model

Every sandbox is an untrusted guest.

- Control runs over SSH on vsock and the qemu-ga channel, never over a network.
- The guest has no vdagent channel, no display socket, and no shared folder.
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
| `list`, `info <name>`            | state, CID, address, TTL left, session      |
| `screenshot <name>`              | display to PNG; `--ocr` adds text           |
| `gc`                             | remove expired and orphaned sandboxes       |
| `base list`, `base build <base>` | show or build Nix bases                     |
| `sleep <phase>`                  | host sleep hook only, not for agents        |

`create` and `run` take `--name`, `--net`, `--mem`, `--cpus`, and `--ttl`.
`exec` and `run` exit with the guest command's status in both output modes, or 124 after `--timeout`, which also stops the command inside the guest.
`destroy --mine` and `list --mine` act on sandboxes started from the caller's Claude Code session or Codex thread, subagents included.
Every removal, by `destroy`, `gc`, a failed `create`, or the MCP server's cleanup, revokes the [workload grants](../../networking/workload-grants.md) of the sandbox it removes; a revoke that fails is reported on stderr and in the journal, and the sandbox is removed anyway.
[sleep.md](sleep.md) covers `sleep` and what host suspend and hibernation do to sandboxes.

```sh
sbx base build nixos
sbx run nixos --in ./repo --out /root/report.txt --to "$TMPDIR" -- sh -c 'python3 repo/check.py > report.txt'
sbx create nixos --name probe --ttl 30m
sbx exec probe -- uname -a
sbx cp probe:/var/log/build.log
sbx destroy probe
```

## Networks

- `--net none`, the default, gives the sandbox no network interface.
- `--net egress` adds one virtio NIC on `vn-sbx`, the bridge of the `sbx` [workload network](../../networking/workloads.md) in `modules/hosts/<host>/workloads.nix`, which sets its egress, isolation, and lease binding.
- The network's resolver ignores the hostnames sandboxes send, so a sandbox cannot look up its peers.
- `create` waits for the guest's DHCP lease and prints its address.
  `list` and `info` read it from the lease file the host's DHCP server keeps for the bridge, not from the guest agent.
- The address is the sandbox's current lease, which the network keeps short.
- Session libvirt joins the bridge through the setuid `qemu-bridge-helper` wrapper.

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
It removes shut-off sandboxes without a managed save, domains without a run directory, and run directories without a domain.
It removes sandboxes past their TTL only while `timedatectl` reports the host clock NTP-synchronized, since an RTC clock right after resume can run hours ahead.
`sbx destroy --expired` refuses with `clock-unsynced` on an unsynced clock.
On a host that never syncs, expired sandboxes stay until `sbx destroy <name>`.
`create`, `exec`, `cp`, `screenshot`, `destroy`, `gc`, `base build`, and every refusal log to the journal under `SYSLOG_IDENTIFIER=sbx`.

## Agents

With the `sbx` row on, Claude Code and Codex get the `sbx` skill from `modules/agents/skills/sbx.nix`, a system-prompt line, and an allow rule for `sbx`.
The Codex allow rule in `modules/agents/codex/_exec-policy.nix` also runs `sbx` outside bwrap, since the CLI writes its state directory and starts user units.
Both clients also start `sbx-mcp`, the `sbx` entry in `modules/agents/mcp/servers.nix`, whose tools take a verb's flags as arguments and return its `--json` document without an approval prompt.
Codex names its thread in every tool call, so `--mine` matches sandboxes from the CLI and the MCP tools alike.
Claude Code passes its session only when it starts the server, so after `/clear` the tools keep the old session until `/mcp` reconnects `sbx`.
Under MCP, the checkout copy root and relative host paths follow the directory the client started in.

## Verify

As the owner:

```sh
systemctl --user status sbx.slice sbx-libvirt.service sbx-gc.timer
sbx base list --json
sbx run nixos -- systemd-detect-virt
sbx run nixos --net egress -- getent hosts cloudflare.com
journalctl --user -t sbx -n 20
```

Failures and their fixes: [troubleshooting](troubleshooting.md).
