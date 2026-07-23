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
- `--age <dur>`: age threshold; `14d`, `2w`, or a bare integer of days.
- `--archive-retention <dur>`: grace period for archive refs (default `90d`).
- `--sweep-archive`: also delete archive refs past the retention window
  (dry-run without `--apply`).
- `--all-worktrees`: process repositories under `$HOME/trees/nixos` in
  addition to the current repository.
