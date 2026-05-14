# AGENTS.md

This file provides guidance to coding agents working in this repository.

> IMPORTANT: Never consider backward compatibility. Eliminate legacy support by default.

> IMPORTANT: This repo currently manages only the `system76` and `tpnix` NixOS hosts for the owner user `vx`. Keep host-specific behavior in the matching `modules/<host>/` tree.

## Critical Safety Rules (Read First)

These rules override all other instructions. Violations are unacceptable.

### Never Make Changes Irrecoverable

Absolutely forbidden:

- `git stash drop` or `git stash clear`
- `git reset --hard` without explicit user approval
- `git clean -fd` or similar destructive operations
- `rm -rf` on user files or directories
- Any command that permanently deletes user work

Required practices:

- Use `rip <path>` instead of `rm` for deletions (recoverable from graveyard)
- Use `git stash` when needed, but never drop stashes
- Allowed stash operations are `git stash`, `git stash list`, `git stash show`, and `git stash apply`
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

- `abort-on-warn`
  - Value: `false`
  - Purpose: Don't abort on warnings
- `extra-experimental-features`
  - Value: `[ "pipe-operators" ]`
  - Purpose: Enable pipe operator syntax in Nix expressions
- `allow-import-from-derivation`
  - Value: `true`
  - Purpose: Required by IFD consumers: `nix-doom-emacs-unstraightened` and `modules/csec/wordlists.nix`
- `experimental-features`
  - Value: `nix-command flakes`
  - Purpose: Enable flakes and new Nix CLI

These settings are mirrored in `build.sh` via `NIX_CONFIGURATION`.

## Quick-Start Checklist

- Sync working tree (`git status -sb`) and review outstanding changes before edits.
  - Status: OK
- Enter dev shell when running commands (`nix develop`).
  - Status: OK
- Use execution playbooks below; confirm prerequisites and post-checks.
  - Status: OK
- Record validation commands in commit messages and PR descriptions.
  - Status: OK
- Never run forbidden commands or modify generated artifacts directly.
  - Status: WARN
- If workflow is missing or ambiguous, escalate to maintainer.
  - Status: WARN

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

Inputs prefixed with `dedupe_` exist for dependency deduplication through `.follows`. If no `follows` references remain, remove the `dedupe_` input.

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
  - Location: `docs/`, `nixos-manual/`
  - Notes: Long-form references and local workflows.
- Secrets
  - Location: `secrets/`
  - Notes: Encrypted payloads managed via `sops.secrets`.
- Generated artifacts
  - Location: `.actrc`, `.gitignore`, `.sops.yaml`, `README.md`
  - Notes: Owned by the files module. Update source definitions instead of editing generated output directly.

### Module Authoring Guidelines (`modules/apps/*`)

Use the standard options namespace and explicit opt-in:

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.<package-name>.extended;
  packageModule = {
    options.programs.<package-name>.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to enable <package-name>.";
      };

      package = lib.mkPackageOption pkgs "<package-name>" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.<package-name> = packageModule;
}
```

## Execution Playbooks

### Branch Workflow

Rule: Use a dedicated worktree and PR for changes. Do not commit directly to `main` unless explicitly approved.

- Create
  - Command: `git worktree add $HOME/trees/nixos/<type>-<name> -b <type>/<name>`
- Work
  - Command: `cd $HOME/trees/nixos/<type>-<name>` then commit changes
- PR
  - Command: `gh pr create --title "<type>(scope): summary" --body "..."`

Branch type should follow Conventional Commits prefixes.

PR body should include:

- `## Summary`
- `## Test plan`

### Development Environment

- Start work
  - Command: `nix develop`
  - Preconditions: Clean tree; network available for substituters.
  - Post-check: Dev tools available (`treefmt`, `pre-commit`, etc.).
- Format sources
  - Command: `nix fmt`
  - Preconditions: Run at repo root.
  - Post-check: No remaining formatting diffs in `git status`.
- Run hooks
  - Command: `nix develop -c pre-commit run --all-files --hook-stage manual`
  - Preconditions: Dev shell ready; workspace writable.
  - Post-check: Exit code 0; review reported TODOs/failures.
- Generate artifacts
  - Command: `nix develop -c write-files`
  - Preconditions: Dev shell ready; managed files may update.
  - Post-check: Review diffs in `.actrc`, `.gitignore`, `.sops.yaml`, `README.md`.

### Validation and Builds

- Verify flake health
  - Command: `nix flake check --accept-flake-config --no-build --offline`
  - Preconditions: Dev shell recommended.
  - Post-check: Exit code 0; resolve reported failures.
- Build host
  - Command: `nix build .#nixosConfigurations.<host>.config.system.build.toplevel`
  - Preconditions: Replace `<host>`.
  - Post-check: Build completes; capture resulting store path.
- Update inputs
  - Command: `nix flake metadata --refresh && nix flake update && nix fmt flake.lock`
  - Preconditions: Clean tree recommended.
  - Post-check: inputs in `flake.lock` are updated.

### GitHub Actions (Local)

- List jobs
  - Command: `nix develop -c gh-actions-list`
  - Preconditions: Dev shell ready
  - Post-check: Lists available workflow jobs
- Run jobs
  - Command: `nix develop -c gh-actions-run`
  - Preconditions: Dev shell ready
  - Post-check: Runs actions locally via `act`
- Dry run
  - Command: `nix develop -c gh-actions-run -n`
  - Preconditions: Dev shell ready
  - Post-check: Shows planned execution

### Troubleshooting

- Unfree package blocked
  - Resolution: Add package to `config.nixpkgs.allowedUnfreePackages` in `modules/meta/nixpkgs-allowed-unfree.nix`.
- Missing app reference
  - Resolution: Ensure that the file is tracked by git.
- Explore config in repl
  - Resolution: `nix develop --accept-flake-config -c nix repl --expr 'import ./.'` then inspect config module imports.

## Coding Style and Verification

- Naming
  - Guidance: Prefer lowercase, hyphenated identifiers. Prefix experiments with `_` to avoid auto-discovery.
- Imports
  - Guidance: Expose modules through namespace exports; avoid literal path imports.
- Validation
  - Guidance: Keep `nix flake check --accept-flake-config` passing. Build host closures before PRs. Use targeted `nix eval`/`nix run` checks when changing modules.

**Skip `nix flake check` after value-level edits**: For nix flakes, skip `nix flake check` after value-level edits to existing lists or attrsets (adding strings, toggling booleans, scalar changes). Reserve it for structural changes: new modules, options, imports, let-binding refactors, argument-shape changes. `treefmt` plus a parse pass is sufficient during iteration.

### Commit and PR Expectations

- Use Conventional Commits: `type(scope): summary`
- Keep one logical concern per commit
- Record validation commands run
- Include screenshots only for user-facing changes
- Stage only files you directly modified

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

## Local Mirrors

- Stylix
  - Path: `/data/git/nix-community-stylix`
  - Use when: Inspect source or apply local patches.
- Home Manager
  - Path: `/data/git/nix-community-home-manager`
  - Use when: Review module behavior or backport fixes.
- Firefox source/docs
  - Path: `/data/git/mozilla-firefox-firefox`
  - Use when: Inspect Firefox source behavior, Gecko internals, preferences, or generated source docs.
- MDN Web Docs
  - Path: `/data/git/mdn-content`
  - Use when: Reference MDN Web/API documentation offline.
- Firefox policies
  - Path: `/data/git/mozilla-policy-templates`
  - Use when: Inspect supported Firefox managed-policy templates and schema.
- Enterprise admin reference
  - Path: `/data/git/mozilla-enterprise-admin-reference`
  - Use when: Check Firefox enterprise policy behavior and syntax documentation.
- LibreWolf settings
  - Path: `/data/git/codeberg-librewolf-settings`
  - Use when: Inspect upstream LibreWolf default settings and uBO assets.
- i3 Docs
  - Path: `/data/git/i3-i3.github.io`
  - Use when: Reference i3 documentation offline.
- Duplicati Docs
  - Path: `/data/git/duplicati-documentation`
  - Use when: Look up `duplicati-cli` commands, options, or backup format.
- nixpkgs
  - Path: `/data/git/NixOS-nixpkgs`
  - Use when: Inspect/patch upstream expressions.
- nixos-hardware
  - Path: `/data/git/NixOS-nixos-hardware`
  - Use when: Pull hardware profiles and troubleshoot host hardware options.
- nixvim
  - Path: `/data/git/nix-community-nixvim`
  - Use when: Examine NixVim modules and options.
- treefmt-nix
  - Path: `/data/git/numtide-treefmt-nix`
  - Use when: Adjust formatter behavior or pinning.
- git-hooks.nix
  - Path: `/data/git/cachix-git-hooks.nix`
  - Use when: Update hook definitions or debug pre-commit failures.
- sops-nix
  - Path: `/data/git/Mic92-sops-nix`
  - Use when: Manage encrypted secret integrations.
- import-tree
  - Path: `/data/git/vic-import-tree`
  - Use when: Review/extend auto-loading behavior.
- files module
  - Path: `/data/git/mightyiam-files`
  - Use when: Update generated artifact sources (e.g., `.gitignore`).

## Practices

- Do what was asked, nothing more and nothing less.
- Use `uv` and `uvx` for all Python work; use `uv run --with <pkg>` for inline/one-off dependencies.
- Prefer editing existing files over creating new ones
- If an issue is upstream, do not add a local wrapper or workaround unless the user explicitly asks for it or approves it.
