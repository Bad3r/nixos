# Old Stash Pruning

`scripts/prune-old-stashes.sh` drops stashes older than an age threshold
(default 14 days) while keeping every dropped stash recoverable: the stash
commit is archived under `refs/stash-archive/<YYYY-MM-DD>/<short-sha>`
before the drop, and archive refs are only deleted by an explicit
`--sweep-archive` past the retention window (default 90 days). The tool
never runs `git stash clear`; every drop is per-stash, and a failed archive
write aborts that stash's drop and fails the run. It is packaged as
`prune-old-stashes`, which the dev shell puts on `PATH`. Issue tracking:
`https://github.com/Bad3r/nixos/issues/202`.

## Manual Use

The command ships with this repository, from its dev shell or as the
`prune-old-stashes` flake package. In a linked worktree the `path:.`
installable is required, since Lix cannot fetch a clean linked worktree as a
`git+file` flake; it works in the main checkout too.

The dev shell installs that same package, so the two routes are one derivation
and either supplies `flock`:

```sh
nix run path:.#prune-old-stashes -- --apply
nix shell path:.#prune-old-stashes -c prune-old-stashes --apply
```

Dry-run report for the current repository (default, changes nothing):

```sh
nix develop path:. -c prune-old-stashes
```

Archive and drop stashes older than 30 days across the current repository
and the worktrees under `$HOME/trees/nixos`:

```sh
nix develop path:. -c prune-old-stashes --age 30d --all-worktrees --apply
```

Linked worktrees share one stash stack; roots resolving to the same common
git dir are processed once.

Scan somewhere other than the default, or several places at once:

```sh
nix develop path:. -c prune-old-stashes --all-worktrees --root ~/trees/nixos --root ~/work/trees
```

## Recovery

A pruned stash stays reachable through its archive ref until a sweep past
the retention window removes it:

```sh
git for-each-ref 'refs/stash-archive/'
git stash apply refs/stash-archive/<YYYY-MM-DD>/<short-sha>
```

## Flags

- `--apply`: perform the archive and drop (dry-run without it).
- `--age <dur>` (also `--age=<dur>`): age threshold; `14d`, `2w`, or a bare
  integer of days, at most 6 digits. `0` selects every stash; unlike
  `--archive-retention 0` it disables nothing.
- `--archive-retention <dur>` (also `--archive-retention=<dur>`): grace period for archive refs (default `90d`).
  `0` disables expiry, matching `--backup-retention-days 0` in
  `scripts/prune-stale-worktrees.sh`. The window is measured from the ref's
  date, not from when it was written, so `1` expires refs dated two or more
  days before today. At most 6 digits. Without `--sweep-archive` it is a usage
  error rather than a silent no-op.
- `--sweep-archive`: also delete archive refs past the retention window
  (dry-run without `--apply`). Refs bearing the current run's archive date are
  never swept, so `--apply --sweep-archive --archive-retention 1` in a single
  invocation cannot delete the archive of a stash it just dropped.
  `--archive-retention 0` disables the sweep outright and says so. A repository
  whose stash list this run could not read or interpret, or in which one of
  this run's own writes failed, is not swept: its archive refs are the only
  copies of stashes dropped by earlier runs.
- `--all-worktrees`: process repositories under each `--root` in addition to
  the current repository.
- `--root <dir>` (also `--root=<dir>`): repeatable; directory scanned by `--all-worktrees`. Defaults
  to `$HOME/trees/nixos`, matching `--root` in
  `scripts/prune-stale-worktrees.sh`. Exactly one level below the root is
  scanned, so each root must directly contain the checkouts; unlike
  `scripts/prune-stale-worktrees.sh`, container directories are not descended
  into. A scanned directory must be the root of the repository it
  resolves to, checked with `git rev-parse --show-prefix`: `--show-toplevel`
  walks up, and a `.git` that does not validate as a git directory does not
  stop that walk, so either check alone would pull in the repository
  enclosing the root. Without `--all-worktrees` it is a usage error
  rather than a silent no-op. A named root that is empty, missing, or that
  contains no checkouts directly beneath it is reported and counted as a
  failure; the default root is exempt, since a host may have no worktrees. A
  scanned directory that has a `.git` which does not resolve is reported as a
  broken checkout and counted under any root, since corruption inside an
  existing tree is not the absence the default root is exempt for.

## Exit Codes

- `0`: success, or a dry run that changed nothing.
- `1`: the run did not complete everything it selected, or could not start at
  all. Causes: an archive write, drop, or archive-ref deletion failed; a
  selected stash moved or vanished before its drop; a stash-list entry was
  unparsable; a stash list or the archive refs could not be read; the common git
  dir of a repository could not be resolved; a named `--root` is missing or
  contains no checkouts; any scanned root, including the default one, holds a
  broken checkout or a directory that is not the root of the repository it
  resolves to; `flock` is not installed; the lock directory could not be
  created, or exists and is not a directory this user owns; another instance
  holds the run lock.
- `64`: usage error, including an unparsable `--age` or `--archive-retention`.

## Concurrency

Runs are serialized by
`${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/prune-old-stashes.<uid>/lock`, the same
guard `scripts/prune-stale-worktrees.sh` uses. Dry runs take the lock too, so a
plan is never printed against a stack another run is pruning. A second
concurrent invocation exits 1 without touching anything.

The lock file sits inside a per-user directory created with mode 700 rather
than directly under the base directory, and the run exits 1 if that directory
is a symlink, is not a directory, or is not owned by this user. Without
`XDG_RUNTIME_DIR` or `TMPDIR` (a cron entry, `ssh host 'scripts/...'`, a
container) the base is `/tmp`: opening a predictable leaf there follows
symlinks and truncates, so another user who creates that name first can empty
any file this uid can write. The sticky bit does not prevent it, since the name
does not exist yet and nothing is being replaced.

The lock is taken with `flock`, so util-linux is a hard requirement rather than
an optimization. The dev-shell wrapper and the `prune-old-stashes` flake package
both carry it in `runtimeInputs`; running `scripts/prune-old-stashes.sh` directly
on a host without it exits 1 naming the missing tool, before any repository is
read. It is checked explicitly because a missing `flock` would otherwise return
127 into the contention branch and be reported as a conflict with a process that
does not exist.

Within a run, stack positions are treated as a snapshot, not as identity: the
position of each selected stash is resolved again from its recorded commit
immediately before the drop, so a `git stash push` from another shell shifts
indices without derailing the run or misidentifying a stash.

Git offers no sha-keyed drop, so one window cannot be closed: a push landing
between the final check and `git stash drop` shifts `stash@{N}` onto a
neighbour. The run lock excludes other invocations of this tool, not the
operator's own shell. `git stash drop` names the commit it removed, so the run
compares it against the one it archived; on a mismatch it archives the commit
that was actually dropped, making it durable instead of unreachable until the
next `git gc`, and reports the mismatch as a failure.

## Tests

```sh
tests/prune-old-stashes/run.sh
```

The suite covers dry-run reporting, apply and archive ordering, recovery
through an archive ref, base-ten age parsing, usage errors, unreadable stash
lists, concurrent pushes and external drops, lock contention, retention
sweeps, and shared stash stacks across linked worktrees.
