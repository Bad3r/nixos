# Chromium Web Apps, Phase 1: Salvage from PR #435

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Phase 1 of 3.** The series replaces the firefoxpwa subsystem with a declarative Chromium web-app module on brave-origin, one PR per phase:

- Phase 1, this file: rescue the two repo-wide fixes stranded in PR #435, then close it.
- Phase 2: `docs/drafts/chromium-webapps-plan-2-remove-firefoxpwa.md`.
- Phase 3: `docs/drafts/chromium-webapps-plan-3-implement.md`, which also carries the decisions table, the verified facts and the self-review for the whole series.

**Goal:** Land the compgen and statix fixes from PR #435 ahead of the removal, so `main` stops carrying a leftover-temporary assertion that reports a pass while verifying nothing, and so statix reaches unstaged files in CI.

**Tech Stack:** Nix (flake-parts, Dendritic pattern), bash, statix, pre-commit.

______________________________________________________________________

## Decisions that bind this phase

Locked before writing this plan. Do not relitigate during execution. The full table for the series is in `docs/drafts/chromium-webapps-plan-3-implement.md`.

| Decision     | Choice                                 | Rationale                                                    |
| ------------ | -------------------------------------- | ------------------------------------------------------------ |
| PR #435      | Close, salvage the two unrelated fixes | The compgen and statix fixes are repo-wide and must survive. |
| PR structure | Three PRs                              | Salvage, remove, implement.                                  |

______________________________________________________________________

## File Structure

### PR 1: salvage (files modified)

- `tests/prune-old-stashes/run.sh`: replace `compgen` guard with `declare -F`
- `modules/meta/build-time-shell.nix`: new flake check banning `compgen` at a command position in build-time shell
- `modules/meta/hooks/statix.nix`: whole-tree branch when invoked with no arguments

______________________________________________________________________

## Tasks

The branch is at `/home/vx/trees/nixos/feat-firefoxpwa-m365`. Its commits 2 and 3 fix repo-wide defects that have nothing to do with firefoxpwa. They must land before the removal so main stops carrying a check that reports a pass while verifying nothing.

### Task 1: Rescue the compgen and statix fixes onto a clean branch

**Files:**

- Modify: `tests/prune-old-stashes/run.sh`

- Create: `modules/meta/build-time-shell.nix`

- Modify: `modules/meta/hooks/statix.nix`

- [ ] **Step 1: Create the worktree**

```bash
cd /home/vx/nixos
git worktree add "$HOME/trees/nixos/fix-build-time-shell" -b "fix/build-time-shell"
```

- [ ] **Step 2: Identify the two commits to cherry-pick**

```bash
cd /home/vx/trees/nixos/feat-firefoxpwa-m365
git log --oneline --format='%h %s' main..HEAD -- \
  tests/prune-old-stashes/run.sh modules/meta/build-time-shell.nix modules/meta/hooks/statix.nix
```

Expected: commit hashes touching only those three paths. Record them as `$COMPGEN_SHA` and `$STATIX_SHA`.

- [ ] **Step 3: Cherry-pick them onto the clean branch**

```bash
cd "$HOME/trees/nixos/fix-build-time-shell"
git cherry-pick "$COMPGEN_SHA" "$STATIX_SHA"
```

Only if the cherry-pick stops on a conflict in `modules/browsers/firefoxpwa/m365-check.nix`, drop that path: it is
deleted in PR 2. Run this against that path alone, then finish the pick:

```bash
git status --short          # confirm m365-check.nix is the only conflicted path
git rm -f modules/browsers/firefoxpwa/m365-check.nix
git cherry-pick --continue
```

Do not resolve with `git checkout --ours .`. During a cherry-pick `--ours` is `HEAD`, which here is the clean branch,
so it resolves every conflicted path to the pre-fix content: run over `.` it discards the compgen and statix hunks
this task exists to rescue, and a trailing `|| true` hides that it happened. `git rm --cached` is also wrong on its
own: it leaves the file in the working tree as untracked, and without `--continue` the cherry-pick is never
finished, so Step 5 would run against a tree still mid-conflict.

If any path other than `m365-check.nix` conflicts, stop and resolve it by reading the hunk. The two commits touch
three files and none of them should conflict on a branch cut from `main`.

- [ ] **Step 4: Verify the compgen fix actually detects what it claims**

```bash
cd "$HOME/trees/nixos/fix-build-time-shell"
rg -n 'declare -F' tests/prune-old-stashes/run.sh
rg -n 'compgen' tests/ modules/ packages/ -g '!modules/meta/build-time-shell.nix'
```

Expected: `declare -F` present in the test runner; no output from the second command.

`modules/meta/build-time-shell.nix` is excluded because it is the check created in Step 3, so it necessarily carries
the literal string it scans for. Without the exclusion the sweep always prints hits and the pass condition has to be
judged by eye.

- [ ] **Step 5: Run the checks**

```bash
cd "$HOME/trees/nixos/fix-build-time-shell"
nix fmt
nix flake check path:. --accept-flake-config --no-build --offline
```

Expected: exit 0.

- [ ] **Step 6: Commit and open the PR**

```bash
cd "$HOME/trees/nixos/fix-build-time-shell"
git add tests/prune-old-stashes/run.sh modules/meta/build-time-shell.nix modules/meta/hooks/statix.nix
git commit -m "fix(checks): stop trusting compgen in build-time shell text

The bash a runCommand builder runs is built without programmable completion, so \`compgen -G\` resolves to no command
and a condition context turns that into false rather than an error. Every leftover-temporary assertion written with it
reported a pass while checking nothing. tests/prune-old-stashes/run.sh used the same builtin for its
defined-but-never-ran guard and passes today only because modules/meta/script-tests.nix puts pkgs.bash on PATH.
Replaced with \`declare -F\`, and checks.build-time-shell now scans modules/, packages/ and tests/ for the builtin at a
command position. statix reached only staged files, so checks.statix-tree runs hook-statix with no arguments.

Validation: nix fmt; nix flake check path:. --accept-flake-config --no-build --offline"
git push -u origin fix/build-time-shell
gh pr create --title "fix(checks): stop trusting compgen in build-time shell text" --body "$(cat <<'EOF'
## Summary

- `compgen -G` is unavailable in `runCommand` bash, so every leftover-temporary assertion using it passed without
  checking anything. Replaced with `declare -F`.
- `checks.build-time-shell` scans `modules/`, `packages/` and `tests/` for the builtin at a command position.
- `checks.statix-tree` runs `hook-statix` with no arguments so lints in unstaged files are reachable in CI.

Rescued from #435, which is being closed unmerged.

## Test plan

- `nix flake check path:. --accept-flake-config --no-build --offline`
- Planted-lint proof: the statix check reports a planted lint before scanning the tree.
EOF
)"
```

- [ ] **Step 7: Close PR #435 with a pointer**

```bash
gh pr close 435 --comment "Closing unmerged. The firefoxpwa subsystem is being replaced by a Chromium web-app module (see docs/drafts/chromium-webapps-plan-3-implement.md); the M365 catalog carries over as data. The two unrelated fixes from this branch (compgen false-pass, whole-tree statix) are rescued in the PR linked above."
```
