# AGENTS.md

This file provides guidance to coding agents working in this repository.

> IMPORTANT: Never consider backward compatibility. Eliminate legacy support by default.

## Critical Safety Rules (Read First)

These rules override all other instructions. Violations are unacceptable.

### Never Make Changes Irrecoverable

Absolutely forbidden:

- Bare `git stash drop` or `git stash clear` (the archived `prune-old-stashes --apply` routes below are the sole exception)
- `git reset --hard` without explicit user approval
- `git clean -fd` or similar destructive operations
- `rm -rf` on user files or directories
- Any command that permanently deletes user work

Required practices:

- Use `rip <path>` instead of `rm` for deletions (recoverable from graveyard)
- Use `git stash` when needed; never drop a stash except through the sanctioned path below
- Allowed stash operations are `git stash`, `git stash list`, `git stash show`, and `git stash apply`
- The one sanctioned drop path is `nix develop path:. -c prune-old-stashes --apply` run from the repository root, which archives each stash under `refs/stash-archive/<date>/<sha>` before dropping it and keeps it recoverable for the retention window (see `docs/reference/stash-prune.md`). It ships only with this repository, either from its dev shell or as the flake package (`nix run path:.#prune-old-stashes -- --apply`); no drop path outside this repository is sanctioned. Like `git stash pop`, it requires explicit user approval before you run it; never issue a bare `git stash drop` yourself
- `git stash pop` requires explicit user approval
- Preserve user changes; if uncertain, ask first
- Before any potentially destructive operation, stop and ask

If something is accidentally deleted:

1. Immediately attempt recovery (stash hash, reflog, `rip` graveyard, etc.)
2. Inform the user exactly what happened and what was recovered
3. Never hide or minimize deletion mistakes

## Repository Overview

This is a NixOS configuration using the Dendritic Pattern (organic configuration growth with automatic module discovery). Files can be moved and nested freely without breaking imports.

Canonical documentation lives under `docs/architecture/`.

## Nix Configuration

Hosts, Home Manager, repo hooks, and CI run Lix
(`pkgs.lixPackageSets.latest.lix`, selected in `modules/base/nix-package.nix`;
RFC issue #282). Lix requires the `flake-self-attrs` experimental feature for
this flake's `self.submodules = true`; it must come from ambient configuration
(`modules/base/nix-settings.nix`, CI installer conf, `build.sh` `NIX_CONFIG`)
because Lix enforces it before `nixConfig` applies. CI installs the same
release through `.github/actions/install-lix` (version and installer digest
pinned together); the `ci-lix-installer-parity` flake check fails when that
pin drifts from `lixPackageSets.latest.lix`.

`flake.nix#nixConfig` carries only pre-evaluation settings needed before the
module graph is loaded:

- `abort-on-warn`
  - Value: `false`
  - Purpose: Don't abort on warnings
- `extra-experimental-features`
  - Value: `[ "pipe-operator" "pipe-operators" ]`
  - Purpose: Enable pipe operator syntax under the Lix name (singular) and
    the CppNix name (plural) for pre-cutover and third-party CppNix
    evaluators
- `allow-import-from-derivation`
  - Value: `true`
  - Purpose: Required by IFD consumer `nix-doom-emacs-unstraightened`

Durable daemon and evaluator settings live in `modules/base/nix-settings.nix`.
Cache topology and download retry settings live in
`modules/hosts/common/nix-substituters.nix`. Inspect those owning files for
current values instead of duplicating the full `nix.settings` set here.

`build.sh` exports `NIX_CONFIG` only as a bootstrap overlay for the Nix commands
it launches before the target system configuration is active.

## Architecture and Module System

### Automatic Module Discovery

All Nix files are automatically imported as flake-parts modules. Files prefixed with `_` are ignored. Avoid literal path imports. Modules register under:

- `flake.nixosModules`
- `flake.homeManagerModules`

### Module Composition Pattern

Hosts compose modules from aggregator namespaces, not literal paths. Use `lib.hasAttrByPath` with `lib.getAttrFromPath` for optional modules to avoid ordering issues.

### Shared Host Modules (`modules/hosts/common/`)

Modules that apply to every host opted into the registry live under `modules/hosts/common/`. The registry is `flake.lib.nixos.hosts.<name>.shareCommon` (declared in `modules/hosts/common/registry.nix`).

Common modules contribute to the aggregate `flake.nixosModules.hosts-common` module. `modules/configurations/nixos.nix` imports that aggregate for each host whose registry entry has `shareCommon = true`, before importing the host-specific module so per-host overrides still win.

Shared device policy that serves multiple optional applications belongs in the common aggregate. For example, `modules/hosts/common/storage-diagnostics.nix` owns NVMe character-device permissions while app modules own their packages and capability wrappers, including compiled argv filters with audited, grammar-aware allowlists that bound those wrappers and the resulting no-sudo operation boundary.

```nix
{ ... }:
let
  body = {
    networking.domain = "local";
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
```

Do NOT iterate over `flake.lib.nixos.hosts` with `lib.filterAttrs`/`lib.mapAttrs` from `modules/hosts/common/*.nix`. Host iteration belongs in `modules/configurations/nixos.nix`, which already owns NixOS system construction. Iterating from a common module that contributes to host configuration can trigger infinite recursion in the flake-parts module evaluator.

`modules/hosts/common/apps-enable.nix` carries the default-on baseline at `lib.mkOverride 1100`; per-host override files (e.g. `modules/tpnix/apps-enable.nix`) layer overrides at `lib.mkOverride 1000` so the host value wins. User overrides at default priority 100 still win over both. `modules/hosts/common/checks.nix` adds a flake-level `nix flake check` assertion that fails when a per-host override duplicates the common baseline value (silent no-op detection).

### Flake Input Deduplication

Use the generated README's "Flake Input Deduplication" section as the canonical
source for local flake input naming and follower relationships. Its source text
is `modules/readme.nix`.

### Repository Layout

- NixOS modules
  - Location: `modules/`
  - Notes: Auto-loaded. Per-host logic under `modules/system76` and `modules/tpnix`; cross-host shared logic under `modules/hosts/common`; other bundles grouped by domain.
- Shared derivations
  - Location: `packages/`
  - Notes: Common build logic shared between modules.
- Helper scripts
  - Location: `scripts/`
  - Notes: Operational tooling.
- Documentation
  - Location: `docs/`
  - Notes: Long-form references and local workflows. The NixOS manual mirror
    lives under `docs/nixos-manual/`.
- Secrets
  - Location: `secrets/`
  - Notes: Encrypted payloads managed via `sops.secrets`.
- Generated artifacts
  - Location: `.actrc`, `.githooks/post-checkout`, `.gitignore`,
    `.gitleaks-gitlink.toml`, `.gitleaks-secrets.toml`, `.gitleaks.toml`,
    `.sops.yaml`, `README.md`
  - Notes: Owned by the files module. Update source definitions instead of editing generated output directly.

### Local Mirrors

The shared mirror root is managed in `modules/git/mirror-root.nix`, and the
common-host mirror list is managed in `modules/hosts/common/mirrors.nix`.
Prefer GitHub `owner/repo` shorthand for GitHub repositories, even when the
input is a `https://github.com/owner/repo/` URL. For example,
`tridactyl/tridactyl` maps to `/data/git/tridactyl-tridactyl`.

The full path inventory lives in `docs/reference/local-mirrors.md`. When a
common mirror is added or removed, keep `docs/reference/local-mirrors.md`,
`docs/architecture/06-reference.md`, and `modules/agents/system-prompt.nix` in
sync with `modules/hosts/common/mirrors.nix`.

## Execution Playbooks

### Branch Workflow

Rule: Use a dedicated worktree and PR for changes. Do not commit directly to `main` unless explicitly approved.

- Create
  - Command: `git worktree add $HOME/trees/nixos/<type>-<name> -b <type>/<name>`
- Work
  - Command: `cd $HOME/trees/nixos/<type>-<name>` then commit changes
  - Rule: give flake commands an explicit `path:.` installable in linked
    worktrees (`nix develop path:.`, `nix flake check path:.`); Lix cannot
    fetch a clean linked worktree as a `git+file` flake because `.git` is a
    file there, not a directory
  - Exception: `nix fmt` hardcodes the `.` installable in `lix/nix/fmt.cc`, so
    it cannot be pointed at `path:.`; the formatter is also a package, so run
    `nix run path:.#treefmt -- .` (or `-- <file>`) instead
  - Exception: anything that writes `flake.lock` back needs an absolute ref,
    because the write goes through Lix's `getAbsPath`
    (`lix/libfetchers/path.cc`); run `nix flake metadata --refresh "path:$PWD"`
    and `nix flake update --flake "path:$PWD"`. `nix flake update` also reads
    positional arguments as input names, which is why the flake goes in
    `--flake` there. `path:.` fetches fine and throws only on the write, so a
    run that changes no lock entry can look like it works
  - Note: a dirty worktree hides all of this, because Lix copies the working
    tree instead of fetching the revision, so the same command passes with
    uncommitted changes present and exits 1 on a clean tree
- PR
  - Command: `gh pr create --title "<type>(scope): summary" --body "..."` (Assign labels)
- Cleanup after merge
  - Command: `scripts/git-worktree-remove-safe.sh $HOME/trees/nixos/<type>-<name>`
  - Follow-up: `git branch -d <type>/<name> && git worktree prune`
  - Why: the repository has the initialized `secrets/` submodule. Plain
    `git worktree remove` can fail on clean worktrees with
    `working trees containing submodules cannot be moved or removed`; the helper
    refuses dirty, ignored, or locked worktrees before using `--force` for that
    Git guard.
- Bulk cleanup of leftovers
  - Command: `scripts/prune-stale-worktrees.sh` (dry-run), `--apply` to act
  - Scope: branches whose upstream is gone plus their worktrees; a semimonthly
    `worktree-prune` user timer runs the safe apply mode on shared hosts.
  - Reference: `docs/reference/worktree-prune.md` for safety guarantees and
    recovery through `refs/prune-backup/*`.

Branch type should follow Conventional Commits prefixes.

PR body should include:

- `## Summary`
- `## Test plan`

### Development Environment

Commands here and in the two sections below are written for a linked worktree,
since that is where the branch workflow above puts the work; dropping `path:.`
gives the primary-checkout form.

- Start work
  - Command: `nix develop path:.`
  - Preconditions: Network available for substituters.
  - Post-check: Dev tools available (`treefmt`, `pre-commit`, etc.).
- Format sources
  - Command: `nix run path:.#treefmt -- .`, or `-- <file>` for a targeted run
  - Preconditions: Run at repo root. `nix fmt` is the primary-checkout form and
    is one of the two cases `path:.` cannot fix, per the exceptions above.
  - Post-check: No remaining formatting diffs in `git status`.
- Run hooks
  - Command: `nix develop path:. -c pre-commit run --all-files --hook-stage manual`
  - Preconditions: Dev shell ready; workspace writable.
  - Post-check: Exit code 0; review reported TODOs/failures.
- Generate artifacts
  - Command: `nix develop path:. --accept-flake-config -c write-files --offline`
  - Preconditions: Dev shell ready; managed files may update.
  - Post-check: Review diffs in `.actrc`, `.githooks/post-checkout`, `.gitignore`, `.gitleaks-gitlink.toml`, `.gitleaks-secrets.toml`, `.gitleaks.toml`, `.sops.yaml`, `README.md`.

### Validation and Builds

- Verify flake health
  - Command: `nix flake check path:. --accept-flake-config --no-build --offline`
  - Preconditions: Dev shell recommended.
  - Post-check: Exit code 0; resolve reported failures.
- Build host
  - Command: `nix build "path:.#nixosConfigurations.$HOSTNAME.config.system.build.toplevel"`
  - Post-check: Build completes; capture resulting store path.
- Update inputs
  - Command: `nix flake metadata --refresh "path:$PWD" && nix flake update --flake "path:$PWD"`
  - Why: the lock-writing exception above, which both links hit. Written bare,
    or with `path:.` on the first link, the chain dies on `nix flake metadata`
    in a linked worktree and never reaches the update. No formatting rung
    follows: `treefmt` excludes `*.lock`, so it emits zero files for
    `flake.lock`.

### GitHub Actions (Local)

- List jobs
  - Command: `nix develop path:. -c gh-actions-list`
  - Preconditions: Dev shell ready
  - Post-check: Lists available workflow jobs
- Run jobs
  - Command: `nix develop path:. -c gh-actions-run`
  - Preconditions: Dev shell ready
  - Post-check: Runs actions locally via `act`
- Dry run
  - Command: `nix develop path:. -c gh-actions-run -n`
  - Preconditions: Dev shell ready
  - Post-check: Shows planned execution

### Troubleshooting

- Unfree package blocked
  - Resolution: Add package to `config.nixpkgs.allowedUnfreePackages` in `modules/meta/nixpkgs-allowed-unfree.nix`.
- Missing reference
  - Resolution: Ensure that the file is tracked by git.
  - Scope: only under the bare `.` form, whose `git+file` fetcher cannot see
    untracked files. `path:.` dumps the directory unfiltered, so it discovers
    an untracked module and evaluates it; there the hazard runs the other way,
    and a check passing locally fails in CI on the pushed revision. Run
    `git status --short` before trusting a `path:.` pass.
- Ignored files under `path:.`
  - Resolution: keep secrets out of the worktree, or pass
    `--allow-secret-copy` to `./build.sh` or `scripts/cache-coverage.sh`
    knowingly.
  - Why: unfiltered also means the `.gitignore` secrets block (`*.agekey`,
    `*.key`, `*.pem`, `*.p12`, `*.pfx`, `.env`, `.env.*`, `id_*`, plus
    `decrypted_*` and `*.dec.*`) protects nothing
    under `path:.`; those files are copied into the world-readable store. The
    last two carry a `secrets/` prefix in the block so git applies them only
    under the gitlink, which leaves a stray copy at the superproject root
    untracked and visible instead of ignored; the guard matches both names
    anywhere it scans, so the anchor scopes git's ignore rule and not the
    guard, and `git check-ignore` does not confirm such a hit.
    `git status --short` does not report ignored files, so use
    `git status --porcelain --ignored=matching`, then
    `git submodule foreach --recursive 'git status --porcelain --ignored=matching'`:
    the superproject form stops at the `secrets/` gitlink, so it misses the
    decrypted SOPS output that submodule ignores through its own `.gitignore`.
    `./build.sh` and `scripts/cache-coverage.sh` run both sweeps and abort,
    through the guard they share in `scripts/lib/secrets-guard.sh`, on the same
    two conditions that select the `path:` ref: a linked worktree and
    `--allow-dirty`. The guard matches the block against every untracked path,
    not the ignored subset, since `git+file` carries only the tracked tree. An
    untracked directory that is itself a git repository is a hit on its name
    alone: `ls-files` stops at that boundary and never opens it, so nothing
    inside reaches the block, while `path:` copies it whole. A primary checkout on the default path keeps the bare ref
    and copies nothing. The guard covers the ref a script evaluates, not the
    one that delivered it, so `nix run path:.#cache-coverage` is unguarded by
    construction (Lix copies while resolving the installable, before the
    wrapper runs), as is any other bare `nix` command run by hand.
- Explore config in repl
  - Resolution: `nix develop path:. --accept-flake-config -c nix repl --expr 'import ./.'` then inspect config module imports.

## Coding Style and Verification

- Naming
  - Guidance: Prefer lowercase, hyphenated identifiers. Prefix experiments with `_` to avoid auto-discovery.
- Imports
  - Guidance: Expose modules through namespace exports; avoid literal path imports.
- Validation
  - Guidance: Keep `nix flake check path:. --accept-flake-config --no-build --offline` passing. Build host closures before PRs. Use targeted `nix eval`/`nix run` checks when changing modules.

**Skip `nix flake check` after value-level edits**: For nix flakes, skip `nix flake check` after value-level edits to existing lists or attrsets (adding strings, toggling booleans, scalar changes). Reserve it for structural changes: new modules, options, imports, let-binding refactors, argument-shape changes. `treefmt` plus a parse pass is sufficient during iteration.

## Secret Management

### Adding a secret with `sops-nix`

1. Encrypt payload: `sops secrets/<name>.yaml`
2. Declare in Nix under `sops.secrets."<namespace>/<name>"`
3. Consume via `config.sops.secrets."<namespace>/<name>".path`

Example:

```nix
sops.secrets."context7/api-key" = {
  sopsFile = ./../../secrets/context7.yaml;
  key = "context7_api_key";
  path = "%r/context7/api-key";
  mode = "0400";
};
```

## Safety and Escalation

Escalate when:

1. A needed workflow is not documented
2. A command fails and remediation is unclear

Pause, summarize the issue, and ask for direction.
