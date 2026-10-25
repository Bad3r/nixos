# sbx sandboxes across host sleep

`sbx sleep pause|resume|save|restore` carries the owner's sandboxes through host suspend and hibernation.
The verbs are for the host sleep hook, not for agents.
The hook in [../libvirt/sleep.md](../libvirt/sleep.md) runs them as each logind user whose `sbx-libvirt.service` has processes, lingering users included.
It owns the systemd units, the ordering, the time caps, and the abort.
The phases live in `packages/sbx/sbx/sleep.py`.

## Phases

Every phase exits 1 on any failure; the hook decides what a failure means.

| Phase     | Runs               | A failure                    |
| --------- | ------------------ | ---------------------------- |
| `pause`   | before suspend     | warns; the host still sleeps |
| `resume`  | after suspend      | joins the wake notification  |
| `save`    | before hibernation | aborts the sleep             |
| `restore` | after hibernation  | joins the wake notification  |

- `pause` and `save` attach only to a daemon that already runs, and a refused connection counts as no sandbox running.
  They never start the daemon.
- `resume` and `restore` touch the daemon only when a record names a sandbox.
  `restore` requires the daemon inside `sbx.slice`, as `create` does.
- Each phase takes the `sbx` state lock, waiting a bounded time, so it never interleaves with a ceiling check, start, or removal.
  A `create` still in its boot wait holds no lock; its deadline runs on the monotonic clock, so the sleep does not count against it.
- A clock that cannot be synced only warns and never fails a phase.

## Suspend

- `pause` suspends every running sandbox and records its name.
  A sandbox already paused stays paused and is not recorded.
- `resume` resumes the recorded sandboxes that are still paused, then sets each one's clock to the host's through qemu-ga, as `virsh domtime --now` does.
- A sandbox past its TTL is resumed too; `sbx gc` removes it once the host clock is synced.

## Hibernate

- `save` first destroys every sandbox past its TTL, but only on an NTP-synchronized host clock.
  On an unsynced clock it warns and saves expired sandboxes with the rest.
  It then managed-saves each running or paused sandbox, recording its name before the save.
- Before the first save it refuses when the save images could take the filesystem of `~/.config/libvirt/qemu/save` below the `minFree` floor.
  It counts each sandbox's declared memory as its image size; the declared-memory ceiling keeps the total under the `sbx.slice` limit.
- The first failed save stops the phase; the sandboxes saved before it come back with the wake.
- The whole phase has a budget below the hook's cap.
  At the budget, or on SIGTERM, `save` aborts the running save job, which leaves that guest running, and exits 1.
- `restore` starts every recorded sandbox from its managed save, expired or not, and leaves expiry to `sbx gc`.
  After hibernation the host clock may still be the RTC's, which can run hours ahead, so a TTL check there could destroy live work.
  `sbx gc` removes expired sandboxes only once the clock is synced; its other reasons, such as a missing run directory, apply at once.
- A recorded sandbox still in a save job, such as one the hook gave up on, is waited for a bounded time and then restored.
  One still saving after that, or one whose restore fails, stays in the record, and `restore` exits 1.
- A sandbox saved while paused comes back paused; one that `pause` recorded too is then resumed.

## Guest clocks

`resume` and `restore` set guest clocks only while `timedatectl` reports the host clock NTP-synchronized.
Otherwise they warn and leave the guest clocks alone, rather than pushing a wrong host time into every sandbox.

## Records

| Path                          | Written by | Cleared by |
| ----------------------------- | ---------- | ---------- |
| `$XDG_RUNTIME_DIR/sbx/paused` | `pause`    | `resume`   |
| `$XDG_RUNTIME_DIR/sbx/saved`  | `save`     | `restore`  |

Records are appended, so a phase that never ran its counterpart is caught up by the next one.
They live under the runtime directory, so a cold boot drops them.
The saved sandboxes then stay shut off with their managed save, and `sbx gc` removes them once their TTL passes on a synced clock.

## Verify

As the owner, after a sleep cycle:

```sh
journalctl -b -u workloads-vm-wake.service | grep -F sandbox=
virsh -c qemu:///session list --all --managed-save
sbx list
```

## A sandbox stays paused or saved after resume

Cause: its resume or restore failed, a save was still running, or the phase stopped before it acted.

```sh
journalctl -b -u workloads-vm-wake.service | grep -E 'warning|error'
cat "$XDG_RUNTIME_DIR/sbx/paused" "$XDG_RUNTIME_DIR/sbx/saved"
```

Fix: a name left in a record is retried by running its phase again; `resume` drops its record even after a failed resume.
A sandbox no record names is brought back by hand, which restores a managed save on `start`:

```sh
sbx sleep restore
virsh -c qemu:///session resume sbx-<name>
virsh -c qemu:///session start sbx-<name>
```

## Hibernation aborts at a sandbox save

Cause: a sandbox failed its save, the phase ran out of time, or the save images would breach the free-space floor.

```sh
journalctl -b -u systemd-hibernate.service | grep -E 'sbx|sandbox'
df -h ~/.config/libvirt/qemu/save
```

Fix: free space, or destroy idle sandboxes with `sbx destroy <name>`, then hibernate again.
