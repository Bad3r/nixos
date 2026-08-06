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

### PR 1: salvage (files created)

- `modules/meta/build-time-shell.nix`: flake check banning `compgen` at a command position in build-time shell

### PR 1: salvage (files modified)

- `tests/prune-old-stashes/run.sh`: replace `compgen` guard with `declare -F`
- `modules/meta/hooks/statix.nix`: add `checks.statix-tree`, which runs `hook-statix` with no arguments, plus the header comment and the widened `perSystem` arguments it needs. The no-argument whole-tree branch inside `hook-statix` is already on `main` (commit `66ac9bac`, an unrelated lefthook migration); what is missing there is a caller that reaches unstaged files in CI.

______________________________________________________________________

## Tasks

The branch is at `/home/vx/trees/nixos/feat-firefoxpwa-m365`. Twelve of its commits fix repo-wide defects that have nothing to do with firefoxpwa. They must land before the removal so main stops carrying a check that reports a pass while verifying nothing.

The count is not stated in the cherry-pick command below, and Step 2 reads it from the branch rather than from this file. The branch kept growing after the first draft of this plan named two commits: the compgen detector alone gained four follow-ups that widen what it catches, and one of them fixes the detector reading `grep` exit 2 as a clean tree. A rescue pinned to a number goes stale the next time the branch moves.

### Task 1: Rescue the compgen and statix fixes onto a clean branch

**Files:**

- Modify: `tests/prune-old-stashes/run.sh`

- Create: `modules/meta/build-time-shell.nix`

- Modify: `modules/meta/hooks/statix.nix`

- [ ] **Step 1: Create the worktree**

```bash
cd /home/vx/nixos
git fetch origin main
git worktree add "$HOME/trees/nixos/fix-build-time-shell" -b "fix/build-time-shell" origin/main
```

- [ ] **Step 2: Identify every commit to cherry-pick**

```bash
cd /home/vx/trees/nixos/feat-firefoxpwa-m365
git log --reverse --oneline --format='%h %s' origin/main..HEAD -- \
  tests/prune-old-stashes/run.sh modules/meta/build-time-shell.nix modules/meta/hooks/statix.nix \
  | tee /tmp/rescue-shas.txt
```

Expected: every commit touching those three paths, oldest first, twelve at the time of writing. `--reverse` matters:
`git log` prints newest first and `git cherry-pick` replays in the order given, so the default order applies the
follow-up fixes before the commits they fix and conflicts on nearly every one.

Confirm none of them carries unrelated content before replaying:

```bash
cut -d' ' -f1 /tmp/rescue-shas.txt | while read -r sha; do
  git show --format='' --name-only "$sha" | rg -v '^$' \
    | rg -v '^(tests/prune-old-stashes/run.sh|modules/meta/build-time-shell.nix|modules/meta/hooks/statix.nix)$' \
    | sed "s|^|$sha |"
done
```

Expected: one line, `<sha> modules/browsers/firefoxpwa/m365-check.nix`, from the first commit. That path is deleted
in PR 2 and Step 3 drops it. Any other line is a commit that would drag firefoxpwa content onto a branch meant to
contain none; read it before continuing.

The range that feeds both commands resolves against `origin/main`, matching Step 1 and Step 6. Step 1's
`git fetch origin main` updates `origin/main` and not local `main`, and refs are shared across worktrees, so a
stale local `main` here lists commits that are already merged alongside the ones to rescue. `modules/meta/hooks/statix.nix` and `tests/prune-old-stashes/run.sh` both exist on
`main` today, so a merged commit touching either satisfies the expectation above and Step 3 cherry-picks a commit
that is already an ancestor of the branch. `modules/meta/build-time-shell.nix` is new, so it cannot produce that.

- [ ] **Step 3: Cherry-pick them onto the clean branch**

```bash
cd "$HOME/trees/nixos/fix-build-time-shell"
git cherry-pick $(cut -d' ' -f1 /tmp/rescue-shas.txt | tr '\n' ' ')
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

If any path other than `m365-check.nix` conflicts, stop and resolve it by reading the hunk. The rescued commits
touch three files and none of them should conflict on a branch cut from `origin/main` when replayed oldest first.

- [ ] **Step 4: Verify the compgen fix actually detects what it claims**

```bash
cd "$HOME/trees/nixos/fix-build-time-shell"
rg -n 'declare -F' tests/prune-old-stashes/run.sh
rg -n -e '^[[:space:]]*!?[[:space:]]*compgen\b|\$\(!?[[:space:]]*compgen\b|(if|elif|while|until|then|else|do|;|&&|\|\|?|\{|\(|\))[[:space:]]+!?[[:space:]]*compgen\b' \
  tests/ modules/ packages/
```

Expected: `declare -F` present in the test runner; no output from the second command.

The second command is the detector's own predicate from `modules/meta/build-time-shell.nix`, not a bare
`rg -n 'compgen'`, so the sweep and the check cannot report different things. A bare string search has no pass
condition here: `modules/meta/build-time-shell.nix` carries the literal it scans for, its planted-lint fixtures pass
`compgen` to `printf` as an argument, and `modules/hm-apps/proton-drive.nix` has carried a comment naming the builtin
since before this branch existed. Excluding paths one at a time hides real reintroductions in whatever file is
excluded next; matching a command position instead reports the one thing that matters. Verified both ways: on `main`
the predicate matches exactly `tests/prune-old-stashes/run.sh`, the site Step 3 replaces, and on the rescued branch it
matches nothing.

- [ ] **Step 5: Run the checks**

```bash
cd "$HOME/trees/nixos/fix-build-time-shell"
nix run path:.#treefmt -- .
nix flake check path:. --accept-flake-config --no-build --offline
```

Expected: exit 0.

- [ ] **Step 6: Commit and open the PR**

Step 3's `git cherry-pick` already committed every rescued change, and its conflict path ends in
`git cherry-pick --continue`, which commits too. Without collapsing them first there is nothing left to commit here:
`git add` stages nothing, `git commit` exits 1 with `nothing added to commit`, and because this block is pasted
rather than run under `set -e` the `git push` and `gh pr create` below still run, publishing #435's original messages
instead of the one written here.

The reset is mixed, not `--soft`. Both produce the same commit from a correct Step 3, since `git add` stages working
tree content either way and so carries Step 5's formatter run in with the picks. They differ in what happens when
Step 3 was not correct: `--soft` keeps whatever the picks left in the index, so a path outside the three rides along
whether or not it is named below, while a mixed reset makes the explicit `git add` the only thing that stages
anything. Step 2's filter reports such a path; this makes the commit refuse to carry it. `m365-check.nix` is absent
from `origin/main`, so the branch never holds it once Step 3's `git rm -f` has run.

```bash
cd "$HOME/trees/nixos/fix-build-time-shell"
git reset origin/main
git add tests/prune-old-stashes/run.sh modules/meta/build-time-shell.nix modules/meta/hooks/statix.nix
git status --short          # confirm nothing outside the three paths is left over
git commit -m "fix(checks): stop trusting compgen in build-time shell text

The bash a runCommand builder runs is built without programmable completion, so \`compgen -G\` resolves to no command
and a condition context turns that into false rather than an error. Every leftover-temporary assertion written with it
reported a pass while checking nothing. tests/prune-old-stashes/run.sh used the same builtin for its
defined-but-never-ran guard and passes today only because modules/meta/script-tests.nix puts pkgs.bash on PATH.
Replaced with \`declare -F\`, and checks.build-time-shell now scans modules/, packages/ and tests/ for the builtin at a
command position, including negated and compound positions, and it no longer reads grep exit 2 as a clean tree.
statix reached only staged files, so checks.statix-tree runs hook-statix with no arguments, skipping the vendored
docs/nixos-manual mirror, and plants a lint so a clean \$out cannot mean a run that walked nothing.

Validation: nix run path:.#treefmt -- .;
nix flake check path:. --accept-flake-config --no-build --offline"
git push -u origin fix/build-time-shell
gh pr create --title "fix(checks): stop trusting compgen in build-time shell text" --body "$(cat <<'EOF'
## Summary

- `compgen -G` is unavailable in `runCommand` bash, so every leftover-temporary assertion using it passed without
  checking anything. Replaced with `declare -F`.
- `checks.build-time-shell` scans `modules/`, `packages/` and `tests/` for the builtin at a command position, plain,
  negated and compound, and treats `grep` exit 2 as an error rather than a clean tree.
- `checks.statix-tree` runs `hook-statix` with no arguments so lints in unstaged files are reachable in CI, skipping
  the vendored `docs/nixos-manual` mirror.

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
