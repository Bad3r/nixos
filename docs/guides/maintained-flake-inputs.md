# Maintained Flake Inputs

## Decision

Support a maintained-input workflow for selected upstream flake inputs, with
remote-locked committed states and temporary local overrides for edit-test loops.
The repository should not commit machine-local `path:` inputs as the normal
state. Published states must point at commits reachable from the configured
remote, while local development can evaluate an external checkout through
`--override-input`.

This keeps upstream-first patching practical without making fresh checkouts
depend on local directories, detached submodules, dirty worktrees, or tribal
knowledge.

## Scope

Use this workflow when a change naturally belongs in an upstream flake input,
such as a package set, module collection, theme framework, or owned companion
flake. Keep using repository-local overlays or wrappers when the change is a
local integration concern, a temporary package workaround, or a host-specific
configuration decision.

Do not use maintained inputs to vendor every upstream source. Each maintained
input needs an explicit reason, a configured upstream remote, and validation that
can prove the committed state remains reproducible.

## Source Mode Policy

| Mode           | Committed flake state                                                                                                                 | Local edit-test state                                           | Use when                                                                                                                               |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Remote locked  | Input URL points at an upstream remote and `flake.lock` pins a reachable commit.                                                      | Optional temporary `--override-input <input> path:<checkout>`.  | Default for maintained inputs that do not need in-tree patching.                                                                       |
| Local override | Same as remote locked.                                                                                                                | External checkout supplied per command via `$<INPUT>_CHECKOUT`. | Ephemeral local patching before adoption as a submodule or before the upstream branch is pushed.                                       |
| Submodule      | Input URL is `./inputs/<flakeInput>` with `flake = true;` and the directory is a git submodule pinned to a reachable upstream commit. | Edits live in the submodule directly; commit gitlink updates.   | Default for maintained inputs that benefit from in-tree patching, branch tracking, and reproducible clones via `--recurse-submodules`. |

The repo-level `inputs.self.submodules = true;` declaration in `flake.nix`
makes submodule contents visible to flake evaluation. The repo's secrets
submodule already relies on the same setting.

Submodule remote convention (fork-and-PR workflow):

- The `.gitmodules` `url` for a maintained input points at the operator's
  fork (e.g. `Bad3r/stylix`), not the canonical upstream. This guarantees
  that fresh clones (`git clone --recurse-submodules`) can always fetch the
  gitlinked commit, including WIP commits that have not yet merged
  upstream. Hosting the fork is a maintenance responsibility: every
  gitlinked SHA must be reachable from the configured branch on the fork.
- Inside the submodule, `origin` is the fork (set automatically from
  `.gitmodules`) and `upstream` is the canonical source the fork tracks.
  The `upstream` remote is operator-managed and must be added after init:
  `git -C inputs/<flakeInput> remote add upstream <canonical-url>`.
- The inventory's `upstream.url` field is the reachability target and
  matches `.gitmodules` (the fork). The optional `forkOf.url` field
  records the canonical source for documentation and tooling.

Machine-local paths, host names, and per-operator checkout roots belong in
operator environment data, not in committed flake input definitions. The
submodule mode keeps the local input path repository-relative
(`./inputs/<flakeInput>`) and reachable across clones.

## Inventory Design

A maintained-input inventory is data exposed as
`flake.lib.meta.maintainedInputs` from `modules/meta/maintained-inputs.nix`.
The inventory is the only place where input-specific policy is recorded.
Validation and wrappers should iterate over this data instead of matching
hard-coded input names.

Required fields:

| Field                  | Purpose                                                                                                                                                                                              |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `flakeInput`           | Root flake input name, for example `nixpkgs` or `stylix`. Also names the submodule directory `inputs/<flakeInput>` in `submodule` mode.                                                              |
| `upstream.url`         | Reachability target. For `submodule` mode, matches the URL recorded in `.gitmodules` (the fork, in a fork-and-PR layout). The gitlinked SHA must be reachable from this URL on the configured `ref`. |
| `upstream.ref`         | Preferred publish ref or branch, recorded as data instead of hard-coded in scripts.                                                                                                                  |
| `forkOf.url`           | Optional canonical source the fork tracks. Informational; documents where upstream PRs land and which remote the `upstream` local remote should point at.                                            |
| `forkOf.ref`           | Optional canonical-source branch the fork is based on. Required when `forkOf.url` is set.                                                                                                            |
| `sourceMode`           | One of `remote-locked`, `local-override`, or `submodule`.                                                                                                                                            |
| `local.pathEnv`        | Optional environment variable that names a local checkout path. Required for `clean-checkout` / `tracked-files` checks under non-submodule modes only.                                               |
| `follows`              | Expected nested input follows relationships that must be preserved.                                                                                                                                  |
| `lockGraph.inputNames` | Expected nested input names for graph-drift detection.                                                                                                                                               |
| `checks`               | Validation classes required before publishing.                                                                                                                                                       |
| `allowLocalSource`     | Optional `true` opt-out from the local-source check. Use only for offline reachability fixtures in non-submodule modes.                                                                              |
| `notes`                | Short rationale and upstreaming expectations.                                                                                                                                                        |

Submodule mode skips `local.pathEnv` and `allowLocalSource`: the checkout path
is derived from the convention `inputs/<flakeInput>` and the lock entry is
expected to carry `type = "path"` with `path = "./inputs/<flakeInput>"`. The
validator rejects any other path or type for a submodule-mode entry.

Example shape (submodule, fork-and-PR layout):

```nix
{
  example-input = {
    flakeInput = "example-input";
    upstream = {
      # Fork URL; matches .gitmodules and is the reachability target.
      url = "https://github.com/<operator>/project.git";
      ref = "main";
    };
    forkOf = {
      # Canonical source the fork tracks; the local `upstream` remote
      # in the submodule should be added pointing at this URL.
      url = "https://github.com/example/project.git";
      ref = "main";
    };
    sourceMode = "submodule";
    follows.nixpkgs = "nixpkgs";
    lockGraph.inputNames = [
      "nixpkgs"
    ];
    checks = [
      "clean-checkout"
      "reachable-commit"
      "follows-preserved"
      "lock-graph"
    ];
    notes = "Use when upstream patches stay in-tree between cycles.";
  };
}
```

Example shape (local override without a submodule):

```nix
{
  ephemeral-input = {
    flakeInput = "ephemeral-input";
    upstream = {
      url = "https://github.com/example/ephemeral.git";
      ref = "main";
    };
    sourceMode = "local-override";
    local.pathEnv = "EPHEMERAL_INPUT_CHECKOUT";
    follows.nixpkgs = "nixpkgs";
    lockGraph.inputNames = [ "nixpkgs" ];
    checks = [
      "clean-checkout"
      "reachable-commit"
      "follows-preserved"
      "lock-graph"
    ];
    notes = "Operator clones the upstream out of tree and exports the env var when patching.";
  };
}
```

The inventory should avoid optional defaults that hide policy. If an input needs
an exception, record the exception explicitly next to the input.

## Validation Design

`scripts/check-maintained-inputs.sh` validates the inventory and lock metadata.
The default mode is offline and suitable for hooks. Add `--fetch` when
publishing a root repository change that depends on a maintained input revision:

```bash
scripts/check-maintained-inputs.sh --fetch
```

Set `MAINTAINED_INPUTS_FETCH=1` to force the same fetch mode from a wrapper,
hook, or CI job without changing the script arguments. The environment override
is read after CLI flags, so it forces fetch validation even when the wrapper
passes `--no-fetch`.

The `maintained-inputs` hook runs at the `pre-push` and `manual` stages of the
pre-commit framework and wraps the same script without `--fetch`. The
`flake.nix` local URL scan is repository-wide because committed local input URLs
are never allowed, with one exception: URLs of the form `./inputs/<flakeInput>`
are reserved for submodule-backed inventory entries and pass the pre-check
unconditionally. The repo-wide `flake.lock` scan then runs against every root
input, exempts inventory-declared inputs from the global rejection, and inside
the per-input loop reapplies a per-entry policy: submodule-mode entries must
carry `type = "path"` with `path = "./inputs/<flakeInput>"`, while other modes
must avoid local paths unless `allowLocalSource = true`.

Validation is split by the failure it catches:

| Check             | Failure caught                                                                                                                                                                                                                                                                 | Data source                                                                                                           |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------- |
| Inventory schema  | Missing fields, unknown check names, duplicate input records.                                                                                                                                                                                                                  | Inventory attrset.                                                                                                    |
| Input existence   | Inventory references an input not present in `flake.nix`.                                                                                                                                                                                                                      | Root flake inputs.                                                                                                    |
| No local URL      | Published `flake.nix` or `flake.lock` points at a `path:` or machine-local source. Runs unconditionally for every root input. Submodule-mode entries instead enforce `path = "./inputs/<flakeInput>"`; other modes opt out per inventory entry with `allowLocalSource = true`. | `flake.nix`, `flake.lock`.                                                                                            |
| Clean checkout    | A publishable local input has unstaged, staged, or untracked state. Submodule mode resolves the checkout to `inputs/<flakeInput>`; other modes use `$<INPUT>_CHECKOUT` named by `local.pathEnv`.                                                                               | `git -C "$checkout" status --porcelain=v1 --untracked-files=all`.                                                     |
| Tracked files     | New files required by evaluation are tracked before testing or publishing.                                                                                                                                                                                                     | Git status in the input checkout.                                                                                     |
| Reachable commit  | The locked revision is not reachable from the configured remote/ref. Submodule mode reads the committed gitlink as the locked revision (path-type lock entries carry no `rev`); other modes read `nodes[$node].locked.rev` from `flake.lock`.                                  | Submodule gitlink (`git ls-files -s inputs/<flakeInput>`) or `flake.lock` plus `git fetch` and `merge-base` ancestry. |
| Follows preserved | Nested input deduplication changed without a reviewed inventory update.                                                                                                                                                                                                        | Inventory `follows` plus flake input declarations or lock metadata.                                                   |
| Lock graph drift  | An input update changed dependency edges beyond the intended input revision.                                                                                                                                                                                                   | Inventory `lockGraph.inputNames` and `flake.lock`.                                                                    |

`clean-checkout` and `tracked-files` encode different policies. `clean-checkout`
rejects any unstaged, staged, or untracked content because `git status` uses
`--untracked-files=all`. `tracked-files` rejects only untracked entries, which
allows iterating on dirty tracked edits while still requiring new files to be
added before evaluation can depend on them. Declare both for the strictest
publish gate, or `tracked-files` alone for a softer policy during active
maintenance.

Local dirty input checkouts are acceptable only for local test commands. They
must fail pre-publish validation. This prevents a successful rebuild from hiding
an unpublished local-only fix.

## Local Workflow

### Submodule mode

Initialize the submodule (a one-time operation after a fresh clone or after a
new maintained input is added to `.gitmodules`) and add the canonical upstream
as a second remote so fetches and merges target the right place:

```bash
git submodule update --init --recursive inputs/<flakeInput>
git -C inputs/<flakeInput> remote add upstream <forkOf.url>
```

`origin` is set automatically from `.gitmodules` and points at the fork.
`upstream` is added locally and is not committed (it lives in the submodule's
local config). Operators who clone the parent repo run the same
`git remote add upstream <forkOf.url>` once.

Add a new maintained input to the inventory as a submodule. Use the fork URL
in `.gitmodules` so the gitlinked commit is always reachable from a fresh
clone:

```bash
git submodule add -b <branch> <fork-url> inputs/<flakeInput>
git -C inputs/<flakeInput> remote add upstream <canonical-url>
```

Patch and test in the submodule directory. The repo-level
`inputs.self.submodules = true;` setting makes the submodule content visible
to flake evaluation without an explicit `--override-input`:

```bash
git -C inputs/<flakeInput> switch -c fix/<short-description>
# edit files
git -C inputs/<flakeInput> add <new-or-changed-files>
nix eval --accept-flake-config --no-write-lock-file \
  .#nixosConfigurations.<host>.config.networking.hostName
```

Publish the submodule branch to the fork so the gitlink is reachable from
`origin` (which matches `.gitmodules`):

```bash
git -C inputs/<flakeInput> commit -m "<change>"
git -C inputs/<flakeInput> push origin HEAD:<publish-ref>
```

Stage the updated gitlink in the parent repository, refresh the lock if needed,
and review only the intended diff:

```bash
git add inputs/<flakeInput>
nix flake update <flakeInput>   # only needed when the input metadata changed
git diff -- flake.lock inputs/<flakeInput> .gitmodules
```

Run maintained-input validation before opening the root repository PR:

```bash
scripts/check-maintained-inputs.sh --fetch
```

The check must fail if the submodule gitlink is missing, its checkout is dirty,
its locked path differs from `./inputs/<flakeInput>`, the upstream commit is
unreachable from `origin` (the fork), or the nested input graph drifted
unexpectedly.

### Local override (ephemeral, non-submodule)

For ad-hoc patching of an input that is not committed as a submodule, clone
the upstream out of tree and export the env var named by `local.pathEnv`:

```bash
git clone <upstream-url> "$MAINTAINED_INPUT_ROOT/<flakeInput>"
export EXAMPLE_INPUT_CHECKOUT="$MAINTAINED_INPUT_ROOT/example-input"

nix eval --accept-flake-config --no-write-lock-file \
  --override-input example-input "path:$EXAMPLE_INPUT_CHECKOUT" \
  .#nixosConfigurations.<host>.config.networking.hostName
```

Do not commit a lock file produced under `--override-input`; the override is
only valid for the current command.

### Sync with upstream

In submodule mode, fetch from the canonical source (the `upstream` remote
added during init), merge into your fork branch, push to `origin`, then
update the parent gitlink:

```bash
git -C inputs/<flakeInput> fetch upstream
git -C inputs/<flakeInput> merge upstream/<forkOf.ref>
git -C inputs/<flakeInput> push origin HEAD
git add inputs/<flakeInput>
```

### Drop local patches

When upstream includes the fix, set the submodule's tracked branch to the
canonical tip, push that state to the fork so the gitlink stays reachable
from `origin`, stage the parent gitlink, and remove any temporary inventory
notes that referenced the work-in-progress branch:

```bash
git -C inputs/<flakeInput> fetch upstream
git -C inputs/<flakeInput> checkout upstream/<forkOf.ref>
git -C inputs/<flakeInput> push origin HEAD:<branch>
git add inputs/<flakeInput>
```

### Recover from conflicts or local-only commits

If validation reports an unreachable or dirty submodule:

1. Stop publishing the root repository change.
2. Inspect the submodule with `git -C inputs/<flakeInput> status --short --branch`.
3. Commit, track, push, or explicitly abandon the in-progress work inside the
   submodule.
4. Stage the parent gitlink only after the submodule commit is reachable from
   the configured remote/ref.
5. Re-run validation.

Do not mask the failure by setting the inventory entry to `allowLocalSource = true` or by editing `flake.lock` by hand.

## Pilot Recommendation

`stylix` is the pilot because the repository is set up to patch it locally
(theming framework with five active follows: `flake-parts`, `nixpkgs`,
`nur` via `dedupe_nur`, `systems`, `tinted-schemes`, and a nested lock graph
of fourteen entries). The committed `inputs/stylix` git submodule pins a
reachable revision on the `Bad3r/stylix` fork; the canonical source it
tracks is `nix-community/stylix` (recorded in the inventory as
`forkOf`). The repo-level `inputs.self.submodules = true;` declaration
makes the submodule content visible to flake evaluation without
per-command overrides.

The pilot should prove this sequence:

1. Keep the inventory entry for `stylix` with `sourceMode = "submodule"`,
   `upstream.url` pointing at the fork (`Bad3r/stylix`), and `forkOf.url`
   pointing at the canonical source (`nix-community/stylix`).
2. Initialize the submodule and add the canonical upstream remote:
   `git submodule update --init --recursive inputs/stylix` then
   `git -C inputs/stylix remote add upstream https://github.com/nix-community/stylix.git`.
3. Patch the upstream code in `inputs/stylix/` and evaluate without flags:
   `nix eval --accept-flake-config --no-write-lock-file .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath`.
4. Track any new upstream files before evaluation depends on them.
5. Push the submodule commit to `origin` (the fork) on a reachable branch.
6. Stage the updated gitlink (`git add inputs/stylix`) in the parent repo.
7. Run `scripts/check-maintained-inputs.sh --fetch` to check clean submodule
   state, reachable commit (against the fork URL), locked path matches the
   convention, preserved follows, and intended lock graph changes.
8. When the change is ready, open a PR upstream against
   `nix-community/stylix` from the fork branch.
9. Document the result in the issue before expanding the workflow to more
   inputs.

## Acceptance Mapping For Issue 258

| Acceptance criterion                                                                    | Decision                                                                                          |
| --------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| RFC decision is recorded.                                                               | Accepted here as a documentation-first policy. Record the PR and summary in the issue.            |
| Generic inventory design is agreed.                                                     | Use `modules/meta/maintained-inputs.nix` as repo-owned Nix data.                                  |
| No hard-coded names or paths.                                                           | Scripts iterate over inventory data. Submodule paths follow the `inputs/<flakeInput>` convention. |
| Nested input relationships are preserved.                                               | `follows` is explicit inventory data and a validation target.                                     |
| Validation catches dirty inputs, untracked files, unreachable commits, and graph drift. | `scripts/check-maintained-inputs.sh` validates these conditions, with `--fetch` for reachability. |
| Documentation covers workflows.                                                         | This guide covers patching, sync, conflict handling, publishing, and rollback.                    |
| Pilot input can be maintained.                                                          | `stylix` is the initial inventory entry.                                                          |
