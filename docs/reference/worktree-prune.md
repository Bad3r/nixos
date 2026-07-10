# Stale Worktree And Branch Pruning

`scripts/prune-stale-worktrees.sh` detects local branches whose upstream
tracking branch is gone after `git fetch --all --prune`, removes the worktree
backing each branch under the scanned roots, and deletes the local branch. A
Home Manager timer (`modules/hm-apps/worktree-prune.nix`, enabled for shared
hosts by `modules/hosts/common/worktree-prune.nix`) runs the safe apply mode
twice a month. Issue tracking:
`https://github.com/Bad3r/nixos/issues/201`.

## Manual Use

Dry-run report over `$HOME/trees` (default, changes nothing, exits 0):

```sh
scripts/prune-stale-worktrees.sh
```

Scan the primary checkout too, so branches without a remaining worktree are
included, then apply:

```sh
scripts/prune-stale-worktrees.sh --repo "$HOME/nixos" --apply
```

The rebuilt user environment also installs the same script as
`prune-stale-worktrees` on `PATH`.

## Flags

- `--apply`: perform safe deletions. Default is dry-run.
- `--force`: additionally prune candidates with unpushed commits or a dirty
  worktree. Implies `--apply`. Never used by the timer.
- `--root DIR` (repeatable): worktree roots to scan. Default `$HOME/trees`.
- `--repo DIR` (repeatable): repositories to scan even without a worktree
  under the roots. Missing paths are reported and skipped.
- `--include GLOB` / `--exclude GLOB` (repeatable): branch-name filters.
- `--backup-retention-days N`: expiry for `refs/prune-backup/*` (default 90,
  `0` disables expiry).
- `--json`: machine-readable summary on stdout instead of text lines.

Exit codes: `0` success, `1` hard error, `2` apply mode was blocked somewhere:
a candidate hit a safety check, a fetch failed, or a `--repo` path was
missing. The systemd unit treats `2` as success because skipped dirty
candidates are expected on a schedule; persistent fetch failures therefore
only surface in the journal, not as a failed unit.

## Safety Model

- Candidates are only branches whose configured upstream is `[gone]` after a
  successful `git fetch --all --prune`. A failed fetch skips the whole
  repository for that run.
- `main`, `master`, the repository default branch, and the branch checked out
  in the primary worktree are never touched.
- Worktree removal goes through `scripts/git-worktree-remove-safe.sh`, which
  refuses dirty, untracked, non-disposable-ignored, locked, and
  dirty-submodule state. The helper is the final arbiter: a worktree the
  dry-run lists as removable can still be refused at apply time, reported as
  `reason=helper-refused`.
- Every deleted branch tip is first preserved as
  `refs/prune-backup/<branch>/<epoch>`. This repository squash-merges PRs, so
  `git branch -d` cannot confirm merged-ness; recoverability comes from the
  backup ref instead, and deletion uses `-D` after the backup exists.
- `pushed=verified` means the branch tip matched the last-seen upstream SHA
  captured before the prune fetch. `pushed=unpushed` blocks the candidate
  without `--force`. `pushed=unverified` means the tracking ref was already
  pruned earlier, so the tip cannot be compared; the candidate is still
  cleaned in apply mode because the backup ref keeps it recoverable.
- `--force` stashes dirty worktree state
  (`git stash push --include-untracked`) before removal, so even forced
  cleanup keeps the work recoverable via `git stash list`.
- Orphan directories under the roots (not a worktree, or a broken `gitdir`
  link such as a worktree whose owning repository moved) are reported and
  never deleted.
- Empty container directories left behind under a root are removed with
  `rmdir`, which cannot delete content.

## flake.lock Exception

A stale worktree whose only dirty path is `flake.lock` counts as disposable
lockfile drift: the drift is discarded with
`git restore --source=HEAD --staged --worktree -- flake.lock` and cleanup
continues on the safe path, reported as `flake-lock-drift=discarded`. If any
other path is dirty, including an untracked `flake.lock`, the candidate is
skipped without `--force`.

## Scheduled Cleanup

`programs.worktreePrune` (Home Manager) provisions a user service and timer:

- `OnCalendar=*-*-01,15 05:00:00` by default. systemd has no `biweekly`
  shorthand; the 1st and 15th give an approximately two-week cadence.
- `Persistent=true`, so a missed run fires after the next login or boot.
- The service runs `prune-stale-worktrees --apply` with the configured roots
  and repos, never `--force`, with `GIT_TERMINAL_PROMPT=0` and a 30 minute
  timeout.
- Shared hosts enable it for the primary user with the `~/nixos` checkout as
  an explicit `--repo`. Disable per host or per user by setting
  `programs.worktreePrune.enable = false;` at a higher priority, or adjust
  `roots`, `repos`, `schedule`, and `backupRetentionDays`.

Inspect scheduled runs:

```sh
systemctl --user list-timers worktree-prune.timer
journalctl --user -u worktree-prune.service
```

## Recovery

- Deleted branch: `git branch <name> "$(git rev-parse 'refs/prune-backup/<name>/<epoch>')"`.
  List backups with `git for-each-ref refs/prune-backup`.
- Force-stashed worktree state: `git stash list` shows
  `prune-stale-worktrees: <branch> <timestamp>` entries; restore with
  `git stash apply`.
- Backup refs expire after `--backup-retention-days` (default 90) on later
  apply runs. Discarded `flake.lock` drift is not preserved.

## Tests

```sh
tests/prune-stale-worktrees/run.sh
```

The suite covers dry-run reporting, safe apply, protected refs, the unpushed
guard, dirty and `flake.lock`-only handling, `--force` stash behavior,
branch-only deletion, multi-root scans, orphan reporting, backup expiry,
fetch failure, filters, and JSON output validity.
