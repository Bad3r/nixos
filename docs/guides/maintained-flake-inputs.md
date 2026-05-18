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

| Mode           | Committed flake state                                                            | Local edit-test state                                              | Use when                                                                                           |
| -------------- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------- |
| Remote locked  | Input URL points at an upstream remote and `flake.lock` pins a reachable commit. | Optional temporary `--override-input <input> path:<checkout>`.     | Default for maintained inputs.                                                                     |
| Local override | Same as remote locked.                                                           | External checkout supplied per command or by a documented wrapper. | Fast local patching before the upstream branch is pushed.                                          |
| Submodule      | Reviewed exception only.                                                         | Submodule checkout under repository control.                       | Only when the source must be part of the repository snapshot and the maintenance cost is accepted. |

Machine-local paths, host names, branch names, and checkout roots belong in
operator environment or inventory data, not in ad hoc shell logic or flake input
definitions.

## Inventory Design

A maintained-input inventory is data exposed as
`flake.lib.meta.maintainedInputs` from `modules/meta/maintained-inputs.nix`.
The inventory is the only place where input-specific policy is recorded.
Validation and wrappers should iterate over this data instead of matching
hard-coded input names.

Required fields:

| Field                  | Purpose                                                                                                       |
| ---------------------- | ------------------------------------------------------------------------------------------------------------- |
| `flakeInput`           | Root flake input name, for example `nixpkgs` or `nix-logseq-git-flake`.                                       |
| `upstream.url`         | Canonical fetch and reachability remote.                                                                      |
| `upstream.ref`         | Preferred publish ref or branch, recorded as data instead of hard-coded in scripts.                           |
| `sourceMode`           | One of `remote-locked`, `local-override`, or `submodule`.                                                     |
| `local.pathEnv`        | Optional environment variable that names a local checkout path. No absolute path is stored in the repository. |
| `follows`              | Expected nested input follows relationships that must be preserved.                                           |
| `lockGraph.inputNames` | Expected nested input names for graph-drift detection.                                                        |
| `checks`               | Validation classes required before publishing.                                                                |
| `notes`                | Short rationale and upstreaming expectations.                                                                 |

Example shape:

```nix
{
  example-input = {
    flakeInput = "example-input";
    upstream = {
      url = "https://github.com/example/project.git";
      ref = "main";
    };
    sourceMode = "local-override";
    local.pathEnv = "EXAMPLE_INPUT_CHECKOUT";
    follows.nixpkgs = "nixpkgs";
    lockGraph.inputNames = [
      "nixpkgs"
    ];
    checks = [
      "clean-checkout"
      "reachable-commit"
      "follows-preserved"
      "lock-graph"
      "no-local-url"
    ];
    notes = "Use for upstream package fixes before they are released.";
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

The `maintained-inputs` pre-commit hook wraps the same script without `--fetch`.
The `flake.nix` local URL scan is repository-wide because committed local input
URLs are never allowed. The inventory `no-local-url` check controls the
per-input `flake.lock` scan.

Validation is split by the failure it catches:

| Check             | Failure caught                                                                     | Data source                                                         |
| ----------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| Inventory schema  | Missing fields, unknown check names, duplicate input records.                      | Inventory attrset.                                                  |
| Input existence   | Inventory references an input not present in `flake.nix`.                          | Root flake inputs.                                                  |
| No local URL      | Published `flake.nix` or `flake.lock` points at a `path:` or machine-local source. | `flake.nix`, `flake.lock`.                                          |
| Clean checkout    | A publishable local input has unstaged, staged, or untracked state.                | `git -C "$checkout" status --porcelain=v1 --untracked-files=all`.   |
| Tracked files     | New files required by evaluation are tracked before testing or publishing.         | Git status in the input checkout.                                   |
| Reachable commit  | The locked revision is not reachable from the configured remote/ref.               | `git fetch` plus ancestry check.                                    |
| Follows preserved | Nested input deduplication changed without a reviewed inventory update.            | Inventory `follows` plus flake input declarations or lock metadata. |
| Lock graph drift  | An input update changed dependency edges beyond the intended input revision.       | Inventory `lockGraph.inputNames` and `flake.lock`.                  |

Local dirty input checkouts are acceptable only for local test commands. They
must fail pre-publish validation. This prevents a successful rebuild from hiding
an unpublished local-only fix.

## Local Workflow

### Initialize a checkout

Clone or reuse an external checkout. The location is operator-local and should
not be committed:

```bash
git clone <upstream-url> "$MAINTAINED_INPUT_ROOT/<input-id>"
```

Set the path variable recorded by the inventory when a wrapper or check uses it:

```bash
export EXAMPLE_INPUT_CHECKOUT="$MAINTAINED_INPUT_ROOT/example-input"
```

### Patch and test locally

Create a branch in the input checkout, edit the upstream source, and make new
files visible to flake evaluation before expecting builds to consume them:

```bash
git -C "$EXAMPLE_INPUT_CHECKOUT" switch -c fix/example
# edit files
git -C "$EXAMPLE_INPUT_CHECKOUT" add <new-or-changed-files>
```

Run the smallest relevant evaluation or build with a temporary override:

```bash
nix eval --accept-flake-config --no-write-lock-file \
  --override-input example-input "path:$EXAMPLE_INPUT_CHECKOUT" \
  .#nixosConfigurations.<host>.config.networking.hostName
```

Use the same override with `nix build` only when evaluation is insufficient.
Do not commit the local override or a lock file that records a local path.

### Publish a reproducible state

Before updating this repository, publish the input branch or otherwise make the
commit reachable from the configured remote:

```bash
git -C "$EXAMPLE_INPUT_CHECKOUT" status --short
git -C "$EXAMPLE_INPUT_CHECKOUT" push <remote> HEAD:<publish-ref>
```

Then update the root flake to the reachable revision and review only the intended
lock changes:

```bash
nix flake lock --update-input example-input
git diff -- flake.lock
```

Run maintained-input validation before opening the root repository PR:

```bash
scripts/check-maintained-inputs.sh --fetch
```

The check must fail if the root repository still depends on a local path, a
dirty checkout, an untracked required file, an unreachable input commit, or an
unreviewed nested input graph change.

### Sync with upstream

Rebase or merge in the input checkout according to the upstream project's normal
workflow. After sync, rerun the local override evaluation and then refresh the
root lock only after the target commit is reachable.

### Drop local patches

When upstream includes the fix, reset the inventory entry back to the upstream
ref if it had a temporary branch, refresh `flake.lock`, and remove any local
operator environment variables or wrapper configuration that are no longer
needed.

### Recover from conflicts or local-only commits

If validation reports an unreachable or dirty input:

1. Stop publishing the root repository change.
2. Inspect the input checkout with `git status --short --branch`.
3. Commit, track, push, or explicitly abandon the input work in that checkout.
4. Refresh the root lock only after the input commit is reachable.
5. Re-run validation.

Do not mask the failure by switching the root input to a local path or by
ignoring dirty input state.

## Pilot Recommendation

`nix-logseq-git-flake` is the first pilot because `flake.nix` already keeps the
committed URL portable and documents `--override-input` for local development.
It also has a small `nixpkgs.follows = "nixpkgs"` edge, which is enough to
exercise follows-preservation checks without starting with a large nested graph.

The pilot should prove this sequence:

1. Keep the inventory entry for `nix-logseq-git-flake`.
2. Patch an external checkout and test with `--override-input`.
3. Track any new upstream files before evaluation depends on them.
4. Push the input commit to the configured remote/ref.
5. Refresh only that input in `flake.lock`.
6. Run `scripts/check-maintained-inputs.sh --fetch` to check clean input state,
   reachable commit, no local URL, preserved follows, and intended lock graph
   changes.
7. Document the result in the issue before expanding the workflow to more inputs.

## Acceptance Mapping For Issue 258

| Acceptance criterion                                                                    | Decision                                                                                          |
| --------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| RFC decision is recorded.                                                               | Accepted here as a documentation-first policy. Record the PR and summary in the issue.            |
| Generic inventory design is agreed.                                                     | Use `modules/meta/maintained-inputs.nix` as repo-owned Nix data.                                  |
| No hard-coded names or paths.                                                           | Scripts iterate over inventory data. Local paths come from environment variables.                 |
| Nested input relationships are preserved.                                               | `follows` is explicit inventory data and a validation target.                                     |
| Validation catches dirty inputs, untracked files, unreachable commits, and graph drift. | `scripts/check-maintained-inputs.sh` validates these conditions, with `--fetch` for reachability. |
| Documentation covers workflows.                                                         | This guide covers patching, sync, conflict handling, publishing, and rollback.                    |
| Pilot input can be maintained.                                                          | `nix-logseq-git-flake` is the initial inventory entry.                                            |
