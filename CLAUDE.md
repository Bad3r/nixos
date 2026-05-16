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

These settings are mirrored in `build.sh` via `NIX_CONFIGURATION`:

- `abort-on-warn = false`
  Do not abort on warnings.
- `extra-experimental-features = [ "pipe-operators" ]`
  Enable pipe operator syntax in Nix expressions.
- `allow-import-from-derivation = true`
  Required by IFD consumers: `nix-doom-emacs-unstraightened` and
  `modules/csec/wordlists.nix`.
- `experimental-features = nix-command flakes`
  Enable flakes and the new Nix CLI.

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
host-specific module so per-host overrides still win.

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

Inputs prefixed with `dedupe_` exist for dependency deduplication through
`.follows`. If no `follows` references remain, remove the `dedupe_` input.

## Ownership Map

- NixOS modules: `modules/`
  Auto-loaded modules. Per-host logic lives under `modules/system76` and
  `modules/tpnix`; cross-host shared logic lives under `modules/hosts/common`;
  other bundles are grouped by domain.
- Shared derivations: `packages/`
  Common build logic shared between modules.
- Helper scripts: `scripts/`
  Operational tooling.
- Documentation: `docs/`, `nixos-manual/`
  Long-form references and local workflows.
- Secrets: `secrets/`
  Encrypted payloads managed through `sops.secrets`.
- Generated artifacts: `.actrc`, `.gitignore`, `.sops.yaml`, `README.md`
  Owned by the files module. Update source definitions instead of editing
  generated output directly.

## Local Mirrors

The shared mirror root is managed in `modules/git/mirror-root.nix`. The
common-host mirror list is managed in `modules/hosts/common/mirrors.nix`.

Prefer GitHub `owner/repo` shorthand for GitHub repositories, even when the
input is an `https://github.com/owner/repo/` URL. For example,
`tridactyl/tridactyl` maps to `/data/git/tridactyl-tridactyl`.

## Branch And PR Workflow

Use a dedicated worktree and PR for changes. Do not commit directly to `main`
unless the user explicitly approves it.

Create a worktree:

```sh
git worktree add "$HOME/trees/nixos/<type>-<name>" -b "<type>/<name>"
```

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
checks for dirty and locked worktrees first, then uses `--force` only for that
Git submodule guard.

Branch type should follow Conventional Commits prefixes. PR bodies should
include:

- `## Summary`
- `## Test plan`

## Development Commands

Start the development environment:

```sh
nix develop
```

Preconditions: clean tree and network access for substituters.
Post-check: dev tools such as `treefmt` and `pre-commit` are available.

Format sources:

```sh
nix fmt
```

Preconditions: run at repo root.
Post-check: no remaining formatting diffs in `git status`.

Run hooks:

```sh
nix develop -c pre-commit run --all-files --hook-stage manual
```

Preconditions: dev shell ready and workspace writable.
Post-check: exit code 0. Review reported TODOs and failures.

Generate managed artifacts:

```sh
nix develop --accept-flake-config -c write-files --offline
```

Post-check: review diffs in `.actrc`, `.gitignore`, `.sops.yaml`, and
`README.md`.

## Validation

Use these repo-specific validation defaults:

- Value-level edits to existing lists or attrsets: `nix fmt` plus a parse or
  targeted eval check. Skip `nix flake check` during iteration.
- Structural changes such as new modules, options, imports, let-binding
  refactors, or argument-shape changes:
  `nix flake check --accept-flake-config --no-build --offline`.
- Host closure changes:
  `nix build ".#nixosConfigurations.$HOSTNAME.config.system.build.toplevel"`.
- Input updates:
  `nix flake metadata --refresh`, `nix flake update`, then `nix fmt flake.lock`.

## GitHub Actions Local Workflow

List jobs:

```sh
nix develop -c gh-actions-list
```

Run jobs locally through `act`:

```sh
nix develop -c gh-actions-run
```

Dry run:

```sh
nix develop -c gh-actions-run -n
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
  Add the package to `config.nixpkgs.allowedUnfreePackages` in
  `modules/meta/nixpkgs-allowed-unfree.nix`.
- Missing reference:
  Ensure the file is tracked by git.
- Need to explore config:
  Run `nix develop --accept-flake-config -c nix repl --expr 'import ./.'`, then
  inspect config module imports.
