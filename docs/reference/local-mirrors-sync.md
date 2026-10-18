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

A failed clone or fetch is retried twice with a growing delay before the spec fails.
Any failed spec fails the whole run once the other specs finish.

## Local work

Changes made inside a mirror survive a sync only as a stash or a backup branch.
`programs.gitMirror.maxBackups` caps each kind per mirror, and the oldest entries go first.
Ignored files never reach a stash, so build output inside a mirror is gone after the next sync.
The sync resets whichever branch is checked out, including one created inside the mirror.

List the saved state from the mirror directory, and move what is needed into a separate clone before newer entries replace it:

```sh
git branch --list 'git-mirror/backup-*'
git stash list
```

## Maintenance

Each clone and sync ends with a foreground `git maintenance run --auto`, whose failures fail the spec.
Every new commit gets a commit-graph layer with the Bloom filters `modules/git/git.nix` enables, keeping `git log -- <path>` and `git blame` fast.
Repacks and multi-pack-index rewrites run only when the geometric strategy's thresholds call for one.
The fetch runs with auto-maintenance off, since that run detaches from the sync and hides its errors.

Mirrors stay out of `maintenance.repo`, so the sync is the only maintenance they get.
A leftover `objects/maintenance.lock` that no process holds open is removed with a log line, because git skips maintenance silently while one exists.
A lock that a process holds fails the spec.

## Unit behavior

- Priority: the sync and both docs services run in `background.slice` with idle I/O scheduling, so they yield CPU and disk to the session.
- Restarts: a failed run restarts after a delay until the unit's [start limit](local-mirrors-troubleshooting.md) trips, and each restart syncs every spec again.
- Docs: a successful run starts the [docs services](local-mirrors-docs.md) through `OnSuccess=`, so a failed run leaves the published trees as they are.
- Switches: `X-SwitchMethod=keep-old` on the three units lets a Home Manager switch update their files without starting or restarting a run.
- Credentials: `GIT_TERMINAL_PROMPT=0` makes a repository that asks for credentials fail instead of hanging the run.
