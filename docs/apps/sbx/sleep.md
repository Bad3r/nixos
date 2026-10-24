# sbx sandboxes across host sleep

`sbx sleep pause|resume|save|restore` carries the owner's sandboxes through host suspend and hibernation.
The verbs are for the host sleep hook, not for agents.
The hook in [../libvirt/sleep.md](../libvirt/sleep.md) runs them as every logged-in user and owns the systemd units, the ordering, and the abort.
The phases live in `packages/sbx/sbx/sleep.py`.

## Phases

| Phase     | Runs               | On failure                 |
| --------- | ------------------ | -------------------------- |
| `pause`   | before suspend     | warns, exits 0             |
| `resume`  | after suspend      | warns, exits 0             |
| `save`    | before hibernation | exits 1, aborts the sleep  |
| `restore` | after hibernation  | exits 1, the wake notifies |

- `pause` and `save` do nothing while `sbx-libvirt.service` is inactive, since no sandbox runs without it.
  They never start the daemon.
- `resume` and `restore` touch the daemon only when a record names a sandbox.
  `restore` requires the daemon inside `sbx.slice`, as `create` does.
- Each phase holds the `sbx` state lock, so it never races a `create` or `destroy`.
  It waits a bounded time for that lock and fails when another command keeps it.

## Suspend

- `pause` suspends every running sandbox and records its name.
  A sandbox already paused stays paused and is not recorded.
- `resume` resumes the recorded sandboxes that are still paused, then sets each one's clock to the host's through qemu-ga, as `virsh domtime --now` does.
- A sandbox past its TTL is resumed too; `sbx gc` removes it on its next run.

## Hibernate

- `save` first destroys every sandbox past its TTL.
  It then managed-saves each running or paused sandbox, recording its name before the save.
- Before the first save it refuses when the save images could take the filesystem of `~/.config/libvirt/qemu/save` below the `minFree` floor.
  It counts each sandbox's declared memory as its image size.
  The declared-memory ceiling keeps the total under the `sbx.slice` memory limit.
- The first failed save stops the phase; the sandboxes saved before it come back with the wake.
- `restore` destroys every sandbox whose TTL ran out during the sleep.
  It then starts each recorded sandbox from its managed save and resyncs the clocks of those that run.
- A sandbox saved while paused comes back paused; one that `pause` recorded too is then resumed.

## Records

| Path                          | Written by | Cleared by |
| ----------------------------- | ---------- | ---------- |
| `$XDG_RUNTIME_DIR/sbx/paused` | `pause`    | `resume`   |
| `$XDG_RUNTIME_DIR/sbx/saved`  | `save`     | `restore`  |

Records are appended, so a phase that never ran its counterpart is caught up by the next one.
They live under the runtime directory, so a cold boot drops them.
The saved sandboxes then stay shut off with their managed save, and `sbx gc` removes them once their TTL passes.

## Verify

As the owner, after a sleep cycle:

```sh
journalctl -b -u workloads-vm-wake.service | grep -F sandbox=
virsh -c qemu:///session list --all --managed-save
sbx list
```

## A sandbox stays paused or saved after resume

Cause: its resume or restore failed, or the whole phase stopped and left its record in place.

```sh
journalctl -b -u workloads-vm-wake.service | grep -E 'warning|error'
ls "$XDG_RUNTIME_DIR/sbx"
```

Fix: with a record left, rerun the phase, which acts only on recorded sandboxes.
Otherwise resume a paused sandbox, or start a saved one, which restores its managed save:

```sh
sbx sleep restore
sbx sleep resume
virsh -c qemu:///session resume sbx-<name>
virsh -c qemu:///session start sbx-<name>
```

## Hibernation aborts at a sandbox save

Cause: a sandbox failed its save, or the save images would breach the free-space floor.

```sh
journalctl -b -u systemd-hibernate.service | grep -E 'sbx|sandbox'
df -h ~/.config/libvirt/qemu/save
```

Fix: free space, or destroy idle sandboxes with `sbx destroy <name>`, then hibernate again.
