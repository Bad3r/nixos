# sbx emulator confinement

A guest that escapes QEMU's device emulation lands in the owner's uid with the owner's supplementary groups, which an unprivileged process cannot drop.
[`sbx`](README.md) therefore keeps every host object those groups open, such as a block device, out of the emulator's sight.

## What QEMU and swtpm see

`sbx-qemu` and the swtpm shim (`packages/sbx/sbx/emulator.py`) put the emulator in a new user, network, and mount namespace, then pivot into a fresh read-only root.
That root holds:

- `/nix/store`, read-only;
- the character devices `kvm`, `null`, `zero`, `full`, `random`, and `urandom` under `/dev`, and no block device;
- `/etc/localtime`, read-only, for guests whose clock follows the host's zone;
- each file a `-blockdev` names, read-only unless a writable format node sits on it: the sandbox's overlay and NVRAM writable, the base and the seed ISO read-only;
- libvirt's per-domain directory under `~/.config/libvirt/qemu/lib/`, where the master key, the SPICE socket, screendumps, and hot-plugged virtiofs sockets live;
- the sockets a `-chardev` names by path, such as a Windows sandbox's TPM socket;
- for swtpm, its state directory, its log, and the directory of its control socket.

Everything else stays out: the rest of `/home`, `/run/user/<uid>/bus`, the systemd user manager's private socket, `/proc`, and `/sys`.
libvirt hands QEMU its monitor, guest agent, console, tap, and vhost descriptors already open, so QEMU opens no other device.
Managed saves and restores travel over a descriptor too.

A path the command line names but the host lacks stays out, so QEMU or swtpm fails on it, and any error while building the root stops the launch before the emulator runs.
A block device, or a character device outside the list, refuses the launch.

## virtiofsd

libvirt starts each runtime share's virtiofsd without `--sandbox`, so virtiofsd uses its default namespace sandbox.
It enters new user, PID, mount, and network namespaces and pivots into the shared directory.

## Limits

- The host kernel is shared: KVM, vhost, the vsock namespace code, and user namespaces stay reachable from an escaped emulator.
- The emulator keeps the host's PID namespace, since libvirt tracks the process it forked and its capability probe reads the pid QEMU writes; Yama's `ptrace_scope` and QEMU's seccomp filter keep it from tracing owner processes, but it can still signal them.
- The supplementary groups stay, so a kernel bug that reaches a device node the groups open still reaches it.
- swtpm sees the directory of every sandbox's TPM socket, since swtpm creates its own socket there.
- The session daemon `virtqemud` runs unconfined as the owner and without seccomp; it parses the guest agent's replies, so a libvirt bug there reaches the owner's whole account.

## Verify

As root, with a sandbox running (`<name>` is its `sbx` name):

```sh
pid=$(cat /run/user/1000/libvirt/qemu/run/sbx-<name>.pid)
readlink /proc/$pid/ns/mnt /proc/1/ns/mnt
find /proc/$pid/root -path /proc/$pid/root/nix/store -prune -o -print
```

The two namespaces differ, and the listing shows only the paths above.
The `sbx-vsock` and `sbx-windows-base` flake checks assert this for QEMU and swtpm, and `workloads-runtime-shares` for virtiofsd.
