# Guests across host sleep

Drop-ins from `modules/workloads/vms/sleep.nix` on the systemd sleep units act on every guest on `qemu:///system`, declared or not.
Nothing happens to system guests while libvirtd is not running.
Each sleep unit, once finished, queues `workloads-vm-wake.service` to bring the guests back, so the resume path never waits on them.

## sbx sandboxes

With the sbx app enabled, each phase also runs `sbx sleep` through `runuser` as every user `loginctl list-users` shows, after the system guests.
The hook records those users, and the wake unit runs `sbx sleep restore`, then `sbx sleep resume`, as each of them.
Each call is bounded in time, and a failure joins the guest failures below.
Other `qemu:///session` guests are not touched; [../sbx/sleep.md](../sbx/sleep.md) covers what each phase does to sandboxes.

## Suspend

- Before the host suspends, each running guest is paused.
  A guest that fails to pause keeps running, and the host suspends anyway.
- After resume, the guests the hook paused are resumed.
  A guest that was already paused before the suspend stays paused.

## Hibernate

Hibernation, hybrid sleep, and suspend-then-hibernate managed-save every running or paused guest before the host sleeps.

- The first failed save, of a guest or of a user's sandboxes, aborts the transition, and the guests already saved are restored.
  A full save directory under `/var/lib/libvirt/qemu/save` fails a save, and so does a transient guest, which libvirt cannot managed-save.
- After resume, the guests the hook saved are started from their save.
  A guest saved while paused, or while in its own sleep (`pmsuspended`), comes back paused, and its clock is not synced; a guest the suspend hook paused comes back running.
- The record of saved guests lives in `/run`, so a cold boot skips the wake unit.
  libvirt restores autostart guests from their save at boot; any other guest stays saved until it is started.

## Guest clocks

After resume, the wake unit sets the clock of each running guest it brought back to the host's, through its QEMU guest agent.
A guest without an agent channel is skipped.
An agent that stays unconnected or fails leaves the guest clock behind.

## Failure reports

Every failure lands in the journal of the unit that hit it.
The wake unit also shows one critical desktop notification in each active graphical session, listing every guest that failed to pause, save, resume, or restore.
A clock that failed to sync only leaves a journal warning.

## Verify

As the owner, after a sleep cycle:

```sh
journalctl -b -u 'systemd-suspend*.service' -u 'systemd-hibernate.service' -u 'systemd-hybrid-sleep.service' -u workloads-vm-wake.service
virsh -r -c qemu:///system list --all --managed-save
```

## Hibernation aborts at a guest save

Cause: a guest failed its managed save, so the hook aborted the transition.

```sh
journalctl -b -u systemd-hibernate.service -u systemd-hybrid-sleep.service -u systemd-suspend-then-hibernate.service | grep -E 'error|saving'
df -h /var/lib/libvirt/qemu/save
```

Fix: free space under the save directory, or shut down the guest the error names, then hibernate again.

## A guest stays paused or shut off after resume

Cause: its resume or restore failed, or the host booted cold instead of resuming.

```sh
journalctl -b -u workloads-vm-wake.service
virsh -r -c qemu:///system list --all --managed-save
```

Fix: resume a paused guest, or start a saved one, which restores its managed save:

```sh
virsh -c qemu:///system resume <name>
virsh -c qemu:///system start <name>
```
