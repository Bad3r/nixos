# sbx

`sbx` runs disposable VMs on the owner's `qemu:///session` for unknown binaries, untrusted repositories, and screenshots of a guest display.
Agents reach it as a plain command; it needs no group, no polkit prompt, and no access to `qemu:///system`.
The app module is `modules/apps/sbx/nixos.nix`; its ceilings come from the host's `sbx` entry in `modules/hosts/<host>/policy.nix`.

## Trust model

Every sandbox is an untrusted guest.

- Control runs over SSH on vsock and the qemu-ga channel, never over a network.
- The guest has no vdagent channel, and no shared folder until a [runtime share](../../networking/workload-shares.md) attaches its `shared` directory or a declared read-only one.
  Only a [GUI base](bases.md#gui-bases) adds a display socket, with clipboard and file transfer off.
- `sbx` accepts no domain XML, no host disk path, and no value above a ceiling.
- Each QEMU runs in its own user and network namespace, and `sbx-qemu` (`packages/sbx/sbx/emulator.py`) starts it only when that namespace's vsock mode is `local`.
- The guest's vhost-vsock device belongs to that namespace, so for the sandbox's whole lifetime it reaches no host vsock listener, whenever that listener starts.
- `exec` and `cp` enter the namespace with `nsenter` to reach the guest's SSH; the module sets `net.vsock.child_ns_mode` to `local` for every new namespace.
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
| `key <name>`, `type <name>`      | keyboard input on a GUI base                |
| `share attach`, `share detach`   | hot-plug or remove a runtime share          |
| `gc`                             | remove expired and orphaned sandboxes       |
| `base list`, `base build <base>` | show or build Nix bases                     |
| `base prepare <image>`           | turn a cloud image into a base, owner only  |
| `sleep <phase>`                  | host sleep hook only, not for agents        |

`create` and `run` take `--name`, `--net`, `--mem`, `--cpus`, `--ttl`, `--gui`, and `--wait`, which [Resources](#resources) covers.
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
- Guests run the NIC at the network's `mtu`: Nix bases take it from the DHCP server, cloud bases from their seed.
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

Nix bases, GUI input, and cloud bases with `base prepare`: [bases](bases.md).
Windows bases, exported from a Windows guest's golden copy and run without SSH: [Windows bases](windows.md).

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

`--wait 30m` turns the running and memory refusals into a wait: the create queues behind earlier waiters and starts once it is first and fits.
A sandbox held in a managed save across host sleep keeps its slot, and a queued large request is never overtaken.
A create without `--wait` refuses while others queue, and a wait that runs out fails with `wait-timeout`.
A request past a per-sandbox ceiling, a `--wait` above the longest TTL less the boot timeout, or a disk limit already passed refuses before it queues.
Both codes name the slot holders under `holders` in the `--json` error, `over-limit` adds a `retry` hint, and `list` shows waiters as `queued` with a `position`.

The TTL counts wall-clock time, host sleep included, from the moment the sandbox starts.

## State

| Path                                | Content                          |
| ----------------------------------- | -------------------------------- |
| `~/.local/share/sbx/<name>/`        | overlay, NVRAM, key, console log |
| `~/.local/share/sbx/<name>/xfer/`   | copies out and screenshots       |
| `~/.local/share/sbx/<name>/shared/` | the read-write runtime share     |
| `~/.local/share/sbx/bases/<base>`   | base out-link or prepared disk   |
| `~/.local/share/sbx/.queue/`        | tickets of creates that wait     |

`sbx-gc.timer` runs `sbx gc` on a schedule.
It removes shut-off sandboxes without a managed save, domains without a run directory, and run directories without a domain.
Past the disk cap or the free-space floor, it detaches `shared` from every sandbox.
It removes sandboxes past their TTL only while `timedatectl` reports the host clock NTP-synchronized, since an RTC clock right after resume can run hours ahead.
`sbx destroy --expired` refuses with `clock-unsynced` on an unsynced clock.
On a host that never syncs, expired sandboxes stay until `sbx destroy <name>`.
`create`, `exec`, `cp`, `share`, `screenshot`, `key`, `type`, `destroy`, `gc`, `base build`, `base prepare`, and every refusal log to the journal under `SYSLOG_IDENTIFIER=sbx`.

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
