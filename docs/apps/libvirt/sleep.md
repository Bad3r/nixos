# Guests across host sleep

Drop-ins from `modules/workloads/vms/sleep.nix` on the systemd sleep units act on every guest on `qemu:///system`, declared or not.
`qemu:///session` guests are not touched.

## Suspend

- Before the host suspends, each running guest is paused.
  A guest that fails to pause keeps running, and the journal records a warning; the host suspends anyway.
- After resume, the guests the hook paused are resumed.
  A guest that was already paused before the suspend stays paused.

## Hibernate

Hibernation, hybrid sleep, and suspend-then-hibernate managed-save every running or paused guest before the host sleeps.

- The first failed save aborts the transition, and the guests already saved are restored.
  A full save directory under `/var/lib/libvirt/qemu/save` fails a save, and so does a transient guest, which libvirt cannot managed-save.
- After resume, the guests the hook saved are started from their save.
  A guest saved while paused comes back paused.
- The record of saved guests lives in `/run`, so after a cold boot nothing restores them.
  Starting such a guest by hand restores its save.

## Guest clocks

After resume, the hook sets the clock of each resumed or restored guest to the host's through its QEMU guest agent.
A guest without an agent channel is skipped.
An agent that stays unconnected or fails leaves a warning in the journal and the guest clock behind.

## Verify

As the owner, after a sleep cycle:

```sh
journalctl -b -u systemd-suspend.service -u systemd-hibernate.service -u systemd-hybrid-sleep.service -u systemd-suspend-then-hibernate.service
virsh -r -c qemu:///system list --all --managed-save
```

## Hibernation aborts at a guest save

Cause: a guest failed its managed save, so the hook aborted the transition.

```sh
journalctl -b -u systemd-hibernate.service | grep -E 'error|saving'
df -h /var/lib/libvirt/qemu/save
```

Fix: free space under the save directory, or shut down the guest the error names, then hibernate again.

## A guest stays shut off after resume

Cause: its restore failed, or the host booted cold instead of resuming.

```sh
virsh -r -c qemu:///system list --all --with-managed-save
```

Fix: start the guest, which restores its managed save:

```sh
virsh -c qemu:///system start <name>
```
