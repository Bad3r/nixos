# sbx troubleshooting

[`sbx`](README.md) reports each refusal with an error code, `error.code` under `--json`.

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
