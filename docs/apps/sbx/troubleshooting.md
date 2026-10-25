# sbx troubleshooting

[`sbx`](README.md) reports each refusal with an error code, `error.code` under `--json`.

## create fails with daemon-outside-slice

Cause: another `qemu:///session` client, such as virt-manager, spawned `virtqemud` before `sbx` did.

```sh
cat "$XDG_RUNTIME_DIR/libvirt/virtqemud.pid"
systemctl --user status sbx-libvirt.service
```

Fix: close that client's session connection, stop the stray `virtqemud`, and rerun the command.

## create fails with libvirt and an sbx-qemu message

Cause: the namespace `sbx-qemu` creates for QEMU is not in `local` vsock mode, or the kernel has no vsock namespaces.

```sh
cat /proc/sys/net/vsock/child_ns_mode
unshare --user --map-current-user --net cat /proc/sys/net/vsock/ns_mode
```

Fix: boot a generation with the `sbx` module, which sets `net.vsock.child_ns_mode` to `local`; the first write locks the value, so a host that wrote `global` first needs a reboot.

## create fails with cannot create a user and network namespace

Cause: the kernel refuses unprivileged user namespaces, which `sbx-qemu` needs to give QEMU its own network namespace.

```sh
sysctl kernel.unprivileged_userns_clone user.max_user_namespaces
unshare --user --map-current-user --net true
```

Fix: allow unprivileged user namespaces (`kernel.unprivileged_userns_clone=1` where the kernel has it, `user.max_user_namespaces` above 0) and retry.

## exec fails with reassociate to namespaces failed

Cause: the sandbox's QEMU shares the caller's user namespace, so it did not start through `sbx-qemu`.

```sh
sbx info <name>
```

Fix: `sbx destroy <name>` and create the sandbox again.

## create fails with over-limit or wait-timeout

Cause: sandboxes that run or sit in a managed save use up the running count or the declared memory, or earlier creates queue for it; the error lists them under `holders`.

```sh
sbx list --json
journalctl --user -t sbx -g queue -n 20
```

Fix: destroy idle sandboxes of the session with `sbx destroy --mine`, or rerun the command with `--wait 30m` as a background task.
A message that names a per-sandbox ceiling, such as `memory must be 256M to ...`, clears only with a smaller request.

## create fails with boot-timeout

Cause: the guest did not answer qemu-ga or SSH on vsock in time; the error carries the console tail.

```sh
sbx base list
```

Fix: rebuild the base with `sbx base build <base>` and retry; a failure that repeats points at the base configuration.
A console tail that shows the boot still progressing needs a longer `sandbox.bootTimeout`.

## create fails with egress-unavailable

Cause: the host declares no `sbx` workload network with `sessionAttach`, or its bridge `vn-sbx` is absent or down.

```sh
ip -br link show vn-sbx
systemctl status workloads-vm-net-sbx.service
```

Fix: switch to the generation that declares the network, or start it with `sudo systemctl restart workloads-vm-net-sbx.service`.

## create fails with no-address

Cause: the guest answered SSH on vsock but took no DHCP lease on `vn-sbx` in time; the error carries the console tail.

```sh
cat /var/lib/libvirt/dnsmasq/vn-sbx.status
grep vn-sbx /etc/qemu/bridge.conf
```

Fix: an empty lease file with the bridge admitted points at the base's DHCP client; rebuild the base and retry.

## exec reports a transport error

Cause: qemu-ga stopped answering after the command started, or `ssh` exited 255 before the deadline; the command may have run in part.
`ssh` also exits 255 when a signal ends the remote command, so an attached command that crashes reads as a transport error too.

```sh
sbx --json info <name>
sbx --json exec <name> -- true
```

Fix: check that the sandbox runs, then rerun the command with `--json`, whose qemu-ga path reports the ending signal under `signal`.

## base prepare fails with owner-only

Cause: the shell carries `CLAUDE_CODE_SESSION_ID` or `CODEX_THREAD_ID`, so `sbx` takes it for an agent session.

```sh
env | grep -E '^(CLAUDE_CODE_SESSION_ID|CODEX_THREAD_ID)='
```

Fix: run `sbx base prepare <image>` from a terminal outside Claude Code and Codex.

## base prepare fails with prepare-failed

Cause: provisioning in the `prepare-<image>` boot exited non-zero or timed out, or the guest did not power off; the error carries the tail of its stderr.

```sh
sbx run nixos --net egress -- getent hosts deb.debian.org
```

Fix: once egress resolves, rerun `sbx base prepare <image>`; a failure that repeats points at the pinned image.
