# Local mirror sync

`git-mirror.service` brings every spec in `programs.gitMirror.repos` up to date under the [mirror root](local-mirrors.md#mirror-root), `programs.gitMirror.jobs` specs at a time.
`git-mirror.timer` starts it on the `programs.gitMirror.timer` calendar and catches up on a missed start the next time the user manager runs.
Both units, and the docs services a sync starts, are defined in `modules/hm-apps/git-mirror.nix`.

Start a sync and read its log, as the owner:

```sh
systemctl --user start git-mirror.service
journalctl --user -u git-mirror.service -n 50 --no-pager
```

## Steps per mirror

A spec without a directory is cloned, gets the [maintenance](#maintenance) run, and is finished.
An existing mirror goes through these steps:

1. Fetch every remote, pruning deleted branches.
2. Stash uncommitted changes, untracked files included.
3. Save `HEAD` on a `git-mirror/backup-<UTC time>` branch when it holds commits the tracking branch lacks.
4. Reset hard to the tracking branch, or to the remote's default branch when `HEAD` tracks none.
5. Delete untracked and ignored files.
6. Run [maintenance](#maintenance).

A failed clone or fetch is retried with a growing delay before the spec fails.
Any failed spec fails the whole run once the other specs finish.

## Local work

Changes made inside a mirror survive a sync only as a stash or a backup branch.
`programs.gitMirror.maxBackups` caps each kind per mirror.
Ignored files never reach a stash, so build output inside a mirror is gone after the next sync.
The sync resets whichever branch is checked out, including one created inside the mirror.

List the saved state from the mirror directory, and move what is needed into a separate clone before later syncs prune it:

```sh
git branch --list 'git-mirror/backup-*'
git stash list
```

## Maintenance

Each clone and sync ends with a foreground `git maintenance run --auto`, whose failures fail the spec.
Each run writes new commits to a commit-graph layer with the Bloom filters `modules/git/git.nix` enables, which keep `git log -- <path>` and `git blame` fast.
Repacks and multi-pack-index rewrites run only when the geometric strategy's thresholds call for one.
The fetch runs with auto-maintenance off, since that run detaches from the sync and hides its errors.

Mirrors stay out of `maintenance.repo`, so the sync is the only maintenance they get.
A leftover `objects/maintenance.lock` that no process holds open is removed with a log line, because git skips maintenance silently while one exists.
A lock that a process holds fails the spec.

## Unit behavior

- Priority: the sync and both docs services yield CPU and disk to the session.
- Restarts: a failed run restarts after a delay until the unit's [start limit](local-mirrors-troubleshooting.md#git-mirrorservice-fails-with-start-limit-hit) trips, and each restart syncs every spec again.
- Switches: a Home Manager switch updates the sync and docs units without starting or restarting a run.
- Credentials: a repository that asks for credentials fails its spec instead of hanging the run.
