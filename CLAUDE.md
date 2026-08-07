# NixOS Repository Instructions

This file contains repository-specific guidance for agents working in this NixOS
configuration. Baseline agent behavior is generated from
`modules/agents/system-prompt.nix`; keep this file focused on project rules that
are not shared agent policy.

Never consider backward compatibility. Eliminate legacy support by default.

## Repository Model

This repository is a NixOS configuration using the Dendritic Pattern: organic
configuration growth with automatic module discovery. Files can be moved and
nested freely without breaking imports when they follow the module discovery
rules.

Canonical architecture documentation lives under `docs/architecture/`.

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

- `abort-on-warn = false`
  Do not abort on warnings.
- `extra-experimental-features = [ "pipe-operator" "pipe-operators" ]`
  Enable pipe operator syntax under the Lix name (singular) and the CppNix
  name (plural) for pre-cutover and third-party CppNix evaluators.
- `allow-import-from-derivation = true`
  Required by IFD consumer `nix-doom-emacs-unstraightened`.

Durable daemon and evaluator settings live in `modules/base/nix-settings.nix`.
Cache topology and download retry settings live in
`modules/hosts/common/nix-substituters.nix`. Inspect those owning files for
current values instead of duplicating the full `nix.settings` set here.

`build.sh` exports `NIX_CONFIG` only as a bootstrap overlay for the Nix commands
it launches before the target system configuration is active.

## Architecture And Module System

### Automatic Module Discovery

All Nix files are automatically imported as flake-parts modules. Files prefixed
with `_` are ignored. Avoid literal path imports.

Modules register under:

- `flake.nixosModules`
- `flake.homeManagerModules`

### Module Composition

Hosts compose modules from aggregator namespaces, not literal paths. Use
`lib.hasAttrByPath` with `lib.getAttrFromPath` for optional modules to avoid
ordering issues.

### Shared Host Modules

Modules that apply to every opted-in host live under `modules/hosts/common/`.
The registry is `flake.lib.nixos.hosts.<name>.shareCommon`, declared in
`modules/hosts/common/registry.nix`.

Common modules contribute to the aggregate `flake.nixosModules.hosts-common`
module. `modules/configurations/nixos.nix` imports that aggregate for each host
whose registry entry has `shareCommon = true`, before importing the
host-specific module so per-host overrides still win. Every host under
`configurations.nixos` must set `shareCommon` explicitly; the host constructor
aborts evaluation for hosts without a registry entry, so a host cannot skip
the common baseline silently.

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

Do not iterate over `flake.lib.nixos.hosts` with `lib.filterAttrs` or
`lib.mapAttrs` from `modules/hosts/common/*.nix`. Host iteration belongs in
`modules/configurations/nixos.nix`, which owns NixOS system construction.
Iterating from a common module that contributes to host configuration can cause
infinite recursion in the flake-parts module evaluator.

`modules/hosts/common/apps-enable.nix` carries the default-on baseline at
`lib.mkOverride 1100`. Per-host override files such as
`modules/tpnix/apps-enable.nix` layer overrides at `lib.mkOverride 1000` so the
host value wins. User overrides at default priority 100 still win over both.
`modules/hosts/common/checks.nix` adds a flake-level `nix flake check`
assertion that fails when a per-host override duplicates the common baseline
value.

### Flake Input Deduplication

Do not restate the local flake input naming table here. Read the generated
README's "Flake Input Deduplication" section, whose source is
`modules/readme.nix`, before changing root input names or follower
relationships.

## Ownership Map

- NixOS modules: `modules/`
  Auto-loaded modules. Per-host logic lives under `modules/system76` and
  `modules/tpnix`; cross-host shared logic lives under `modules/hosts/common`;
  other bundles are grouped by domain.
- Shared derivations: `packages/`
  Common build logic shared between modules.
- Helper scripts: `scripts/`
  Operational tooling.
- Documentation: `docs/`
  Long-form references and local workflows. The NixOS manual mirror lives under
  `docs/nixos-manual/`.
- Secrets: `secrets/`
  Encrypted payloads managed through `sops.secrets`.
- Generated artifacts: `.actrc`, `.githooks/post-checkout`, `.gitignore`,
  `.gitleaks-gitlink.toml`, `.gitleaks-secrets.toml`, `.gitleaks.toml`,
  `.sops.yaml`, `README.md`
  Owned by the files module. Update source definitions instead of editing
  generated output directly.

## Local Mirrors

The shared mirror root is managed in `modules/git/mirror-root.nix`. The
common-host mirror list is managed in `modules/hosts/common/mirrors.nix`.

Prefer GitHub `owner/repo` shorthand for GitHub repositories, even when the
input is an `https://github.com/owner/repo/` URL. For example,
`tridactyl/tridactyl` maps to `/data/git/tridactyl-tridactyl`.

The full path inventory lives in `docs/reference/local-mirrors.md`. When a
common mirror is added or removed, keep `docs/reference/local-mirrors.md`,
`docs/architecture/06-reference.md`, and `modules/agents/system-prompt.nix` in
sync with `modules/hosts/common/mirrors.nix`.

## Branch And PR Workflow

Use a dedicated worktree and PR for changes. Do not commit directly to `main`
unless the user explicitly approves it.

Create a worktree:

```sh
git worktree add "$HOME/trees/nixos/<type>-<name>" -b "<type>/<name>"
```

In a linked worktree, give flake commands an explicit `path:.` installable
(`nix develop path:.`, `nix flake check path:.`, `nix eval "path:.#..."`):
Lix cannot fetch a clean linked worktree as a `git+file` flake because `.git`
is a file there, not a directory. The repo hooks already do this.

Two cases take a different form, because appending `path:.` does not fix
them:

- `nix fmt`. Lix hardcodes the `.` installable in `lix/nix/fmt.cc`, so
  `nix fmt path:.` passes `path:.` to treefmt as a path argument and still
  resolves `.` as the flake. The formatter is also a package, so run
  `nix run path:.#treefmt -- .` instead, or `-- <file>` for a targeted run.
- Anything that writes `flake.lock` back. That write goes through Lix's
  `getAbsPath` (`lix/libfetchers/path.cc`), which throws
  `cannot fetch input 'path:.' because it uses a relative path`, so the ref
  must be absolute. This covers `nix flake metadata --refresh "path:$PWD"`,
  which locks the flake, as well as `nix flake update --flake "path:$PWD"`;
  `nix flake update` also reads positional arguments as input names, which is
  why the flake goes in `--flake` there. A run that resolves to no lock change
  never writes and so never throws, which is why the relative form can look
  like it works. It fails exactly when the lock is out of sync, which is the
  state the input-update ladder is run in.

A dirty worktree hides all of this, because Lix copies the working tree instead
of fetching the revision, so a command that happens to run with uncommitted
changes present works and the same command run on a clean tree exits 1.

Work in that tree, then create a PR:

```sh
gh pr create --title "<type>(scope): summary" --body "..."
```

After the PR merges, remove the finished worktree through the safe helper:

```sh
scripts/git-worktree-remove-safe.sh "$HOME/trees/nixos/<type>-<name>"
git branch -d "<type>/<name>"
git worktree prune
```

This repo has an initialized `secrets/` submodule, so plain
`git worktree remove` can fail on clean worktrees with
`working trees containing submodules cannot be moved or removed`. The helper
checks for dirty, ignored, and locked worktrees first, then uses `--force` only
for that Git submodule guard.

Leftover branches whose remote branch was deleted, and the worktrees backing
them, are pruned by `scripts/prune-stale-worktrees.sh` (dry-run by default)
and by a semimonthly `worktree-prune` user timer on shared hosts. See
`docs/reference/worktree-prune.md` for flags, safety guarantees, and recovery
through `refs/prune-backup/*`.

Branch type should follow Conventional Commits prefixes. PR bodies should
include:

- `## Summary`
- `## Test plan`

## Development Commands

As in `## Validation` below, these are written for a linked worktree, since that
is where the branch workflow above puts the work; dropping `path:.` gives the
primary-checkout form.

Start the development environment:

```sh
nix develop path:.
```

Preconditions: network access for substituters.
Post-check: dev tools such as `treefmt` and `pre-commit` are available.

Format sources:

```sh
nix run path:.#treefmt -- .
```

Preconditions: run at repo root. `nix fmt` is the primary-checkout form; it is
one of the two cases `path:.` cannot fix, the other being any command that
writes `flake.lock` back, so a linked worktree goes through the package
instead, or `-- <file>` for a targeted run.
Post-check: no remaining formatting diffs in `git status`.

Run hooks:

```sh
nix develop path:. -c pre-commit run --all-files --hook-stage manual
```

Preconditions: dev shell ready and workspace writable.
Post-check: exit code 0. Review reported TODOs and failures.

Generate managed artifacts:

```sh
nix develop path:. --accept-flake-config -c write-files --offline
```

Post-check: review diffs in `.actrc`, `.githooks/post-checkout`, `.gitignore`,
`.gitleaks-gitlink.toml`, `.gitleaks-secrets.toml`, `.gitleaks.toml`,
`.sops.yaml`, and `README.md`.

## Validation

Use these repo-specific validation defaults. Commands are written for a linked
worktree, since that is where the branch workflow above puts the work; the plain
`.` forms work in the primary checkout as well.

- Value-level edits to existing lists or attrsets:
  `nix run path:.#treefmt -- .` plus a parse or targeted eval check. Skip
  `nix flake check` during iteration.
- Structural changes such as new modules, options, imports, let-binding
  refactors, or argument-shape changes:
  `nix flake check path:. --accept-flake-config --no-build --offline`.
- Host closure changes:
  `nix build "path:.#nixosConfigurations.$HOSTNAME.config.system.build.toplevel"`.
- Overlay or override changes that can affect binary-cache coverage:
  `scripts/cache-coverage.sh --host $HOSTNAME` (evaluation plus narinfo
  probes, no builds; see `docs/reference/cache-coverage.md`). The script
  resolves its own `path:` ref.
- Input updates: `nix flake metadata --refresh "path:$PWD"`, then
  `nix flake update --flake "path:$PWD"`. See the worktree note above for why
  neither is `path:.`: both write `flake.lock` back. `flake.lock` is excluded
  from treefmt, so there is no formatting rung after it.

## GitHub Actions Local Workflow

List jobs:

```sh
nix develop path:. -c gh-actions-list
```

Run jobs locally through `act`:

```sh
nix develop path:. -c gh-actions-run
```

Dry run:

```sh
nix develop path:. -c gh-actions-run -n
```

Reserve expensive local workflow runs for changes that affect workflow paths or
when the user explicitly asks for them. Prefer static lint, parsed script
inspection, or job listing first when those checks can catch the failure.

## Coding Style

- Prefer lowercase, hyphenated identifiers.
- Prefix experiments with `_` to avoid auto-discovery.
- Expose modules through namespace exports.
- Avoid literal path imports.

## Documentation

When a change needs documentation under the generated baseline rules, update an
existing repo surface such as `docs/`, `README.md`, `CLAUDE.md`, or `AGENTS.md`
instead of creating a new docs surface by default.

## Secret Management

To add a secret with `sops-nix`:

1. Encrypt the payload: `sops secrets/<name>.yaml`.
2. Declare it in Nix under `sops.secrets."<namespace>/<name>"`.
3. Consume it via `config.sops.secrets."<namespace>/<name>".path`.

Example:

```nix
sops.secrets."context7/api-key" = {
  sopsFile = ./../../secrets/context7.yaml;
  key = "context7_api_key";
  path = "%r/context7/api-key";
  mode = "0400";
};
```

## Troubleshooting

- Unfree package blocked:
  Add the package to the flake-parts `nixpkgs.allowedUnfreePackages` option
  from the module that needs it (option declared in
  `modules/meta/nixpkgs-allowed-unfree.nix`). There is no NixOS-scope
  allowlist option; host-level `nixpkgs.allowedUnfreePackages` fails eval.
- Missing reference:
  Ensure the file is tracked by git. That fixes it only under the bare `.`
  form, whose `git+file` fetcher cannot see untracked files. `path:.` dumps
  the directory unfiltered, so it discovers an untracked module and evaluates
  it. The hazard there runs the other way: a check that passes locally on
  `path:.` fails in CI, which fetches the pushed revision. Run
  `git status --short` before trusting a `path:.` pass.
- Ignored files under `path:.`:
  Unfiltered also means the `.gitignore` secrets block (`*.agekey`, `*.key`,
  `*.pem`, `*.p12`, `*.pfx`, `.env`, `.env.*`, `id_*`) protects nothing: those
  files are copied into the world-readable store. `git status --short` does
  not surface them, since ignored files are not reported; use
  `git status --porcelain --ignored=matching`, then
  `git submodule foreach --recursive 'git status --porcelain --ignored=matching'`,
  because the superproject form stops at the `secrets/` gitlink and so misses
  the decrypted SOPS output that submodule ignores through its own
  `.gitignore`. `./build.sh` runs both sweeps and aborts before it builds,
  overridable with `--allow-secret-copy`, but a bare `nix` command run by hand
  has no such guard.
- Need to explore config:
  Run `nix develop path:. --accept-flake-config -c nix repl --expr 'import ./.'`,
  then inspect config module imports.
