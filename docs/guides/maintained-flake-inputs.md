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

Machine-local paths, host names, and per-operator checkout roots belong in
operator environment data, not in committed flake input definitions. The
submodule mode keeps the local input path repository-relative
(`./inputs/<flakeInput>`) and reachable across clones; only the submodule URL
in `.gitmodules` should reference the upstream remote.

## Inventory Design

A maintained-input inventory is data exposed as
`flake.lib.meta.maintainedInputs` from `modules/meta/maintained-inputs.nix`.
The inventory is the only place where input-specific policy is recorded.
Validation and wrappers should iterate over this data instead of matching
hard-coded input names.

Required fields:

| Field                  | Purpose                                                                                                                                                |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `flakeInput`           | Root flake input name, for example `nixpkgs` or `stylix`. Also names the submodule directory `inputs/<flakeInput>` in `submodule` mode.                |
| `upstream.url`         | Canonical fetch and reachability remote. Must match the URL recorded for the matching submodule in `.gitmodules` when `sourceMode = "submodule"`.      |
| `upstream.ref`         | Preferred publish ref or branch, recorded as data instead of hard-coded in scripts.                                                                    |
| `sourceMode`           | One of `remote-locked`, `local-override`, or `submodule`.                                                                                              |
| `local.pathEnv`        | Optional environment variable that names a local checkout path. Required for `clean-checkout` / `tracked-files` checks under non-submodule modes only. |
| `follows`              | Expected nested input follows relationships that must be preserved.                                                                                    |
| `lockGraph.inputNames` | Expected nested input names for graph-drift detection.                                                                                                 |
| `checks`               | Validation classes required before publishing.                                                                                                         |
| `allowLocalSource`     | Optional `true` opt-out from the local-source check. Use only for offline reachability fixtures in non-submodule modes.                                |
| `notes`                | Short rationale and upstreaming expectations.                                                                                                          |

Submodule mode skips `local.pathEnv` and `allowLocalSource`: the checkout path
is derived from the convention `inputs/<flakeInput>` and the lock entry is
expected to carry `type = "path"` with `path = "./inputs/<flakeInput>"`. The
validator rejects any other path or type for a submodule-mode entry.

Example shape (submodule):

```nix
{
  example-input = {
    flakeInput = "example-input";
    upstream = {
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
new maintained input is added to `.gitmodules`):

```bash
git submodule update --init --recursive inputs/<flakeInput>
```

Add a new maintained input to the inventory as a submodule:

```bash
git submodule add -b <branch> <upstream-url> inputs/<flakeInput>
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

Publish the submodule branch upstream so the gitlink is reachable from the
configured remote:

```bash
git -C inputs/<flakeInput> commit -m "<change>"
git -C inputs/<flakeInput> push <remote> HEAD:<publish-ref>
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
unreachable, or the nested input graph drifted unexpectedly.

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

In submodule mode, fetch and merge inside the submodule directory according to
the upstream project's normal workflow, then commit the gitlink update in the
parent repository:

```bash
git -C inputs/<flakeInput> fetch <remote>
git -C inputs/<flakeInput> merge <remote>/<branch>
git add inputs/<flakeInput>
```

### Drop local patches

When upstream includes the fix, set the submodule back to the upstream branch
tip, stage the gitlink, and remove any temporary inventory notes that referenced
the work-in-progress branch:

```bash
git -C inputs/<flakeInput> fetch <remote>
git -C inputs/<flakeInput> checkout <remote>/<branch>
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
reachable upstream commit; the repo-level `inputs.self.submodules = true;`
declaration makes the submodule content visible to flake evaluation without
per-command overrides.

The pilot should prove this sequence:

1. Keep the inventory entry for `stylix` with `sourceMode = "submodule"`.
2. Patch the upstream code in `inputs/stylix/` and evaluate without flags:
   `nix eval --accept-flake-config --no-write-lock-file .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath`.
3. Track any new upstream files before evaluation depends on them.
4. Push the submodule commit to `https://github.com/nix-community/stylix.git`
   (or a fork) on a reachable branch.
5. Stage the updated gitlink (`git add inputs/stylix`) in the parent repo.
6. Run `scripts/check-maintained-inputs.sh --fetch` to check clean submodule
   state, reachable commit, locked path matches the convention, preserved
   follows, and intended lock graph changes.
7. Document the result in the issue before expanding the workflow to more
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
