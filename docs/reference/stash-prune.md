# Old Stash Pruning

`scripts/prune-old-stashes.sh` drops stashes older than an age threshold
(default 14 days) while keeping every dropped stash recoverable: the stash
commit is archived under `refs/stash-archive/<YYYY-MM-DD>/<short-sha>`
before the drop, and archive refs are only deleted by an explicit
`--sweep-archive` past the retention window (default 90 days). The tool
never runs `git stash clear`; every drop is per-stash, and a failed archive
write aborts that stash's drop and fails the run. The dev shell installs the
same script as `prune-old-stashes` on `PATH`. Issue tracking:
`https://github.com/Bad3r/nixos/issues/202`.

## Manual Use

Dry-run report for the current repository (default, changes nothing):

```sh
prune-old-stashes
```

Archive and drop stashes older than 30 days across the current repository
and the worktrees under `$HOME/trees/nixos`:

```sh
prune-old-stashes --age 30d --all-worktrees --apply
```

Linked worktrees share one stash stack; roots resolving to the same common
git dir are processed once.

## Recovery

A pruned stash stays reachable through its archive ref until a sweep past
the retention window removes it:

```sh
git for-each-ref 'refs/stash-archive/'
git stash apply refs/stash-archive/<YYYY-MM-DD>/<short-sha>
```

## Flags

- `--apply`: perform the archive and drop (dry-run without it).
- `--age <dur>`: age threshold; `14d`, `2w`, or a bare integer of days. `0`
  selects every stash; unlike `--archive-retention 0` it disables nothing.
- `--archive-retention <dur>`: grace period for archive refs (default `90d`).
  `0` disables expiry, matching `--backup-retention-days 0` in
  `scripts/prune-stale-worktrees.sh`. Use `1` to expire refs older than a day.
- `--sweep-archive`: also delete archive refs past the retention window
  (dry-run without `--apply`). Refs bearing the current run's archive date are
  never swept, so `--apply --sweep-archive --archive-retention 1` in a single
  invocation cannot delete the archive of a stash it just dropped.
  `--archive-retention 0` disables the sweep outright and says so.
- `--all-worktrees`: process repositories under `$HOME/trees/nixos` in
  addition to the current repository.

## Exit Codes

- `0`: success, or a dry run that changed nothing.
- `1`: at least one archive write, drop, or archive-ref deletion failed, a
  stash list or the archive refs could not be read, or another instance holds
  the run lock.
- `64`: usage error, including an unparsable `--age` or `--archive-retention`.

## Concurrency

Runs are serialized by `${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/prune-old-stashes.<uid>.lock`,
the same guard `scripts/prune-stale-worktrees.sh` uses. Dry runs take the lock
too, so a plan is never printed against a stack another run is pruning. A
second concurrent invocation exits 1 without touching anything.

Within a run, stack positions are treated as a snapshot, not as identity: the
position of each selected stash is resolved again from its recorded commit
immediately before the drop, so a `git stash push` from another shell shifts
indices without derailing the run or misidentifying a stash.

## Tests

```sh
tests/prune-old-stashes/run.sh
```

The suite covers dry-run reporting, apply and archive ordering, recovery
through an archive ref, base-ten age parsing, usage errors, unreadable stash
lists, concurrent pushes and external drops, lock contention, retention
sweeps, and shared stash stacks across linked worktrees.
