# Repository Guidelines

## Project Structure & Module Organization

This file governs the `docs/` subtree. Keep documentation scoped to existing folders:

- `architecture/`: canonical design docs for module system and composition.
- `guides/`, `usage/`, `reference/`: task-oriented instructions and reference material.
- Domain folders (for example `cloudflare/`, `sops/`, `usbguard/`): product-specific docs.

Prefer updating an existing page over adding a new one. Use clear, repo-relative links (for example `../architecture/index.md`) and keep host/user assumptions aligned to the single System76 host and `vx` user model.

## Build, Test, and Development Commands

Run commands from repo root (`/home/vx/nixos`):

- `nix develop`: enter the dev shell with formatter and validation tools.
- `nix fmt`: apply repository formatting rules.
- `nix develop -c pre-commit run --all-files --hook-stage manual`: run all hooks.
- `nix flake check --accept-flake-config --no-build --offline`: validate flake/module health without building.

Use `rg -C 5 'pattern' docs/` to find and update related content before writing new docs.

## Coding Style & Naming Conventions

Use concise Markdown with descriptive headings (`##`, `###`) and short paragraphs. Keep examples executable and explicit:

```bash
nix develop -c pre-commit run --all-files --hook-stage manual
```

Prefer lowercase, hyphenated filenames (for example `module-discovery.md`). Use backticks for commands, paths, options, and identifiers.

## Testing Guidelines

There is no docs-only test framework. Validation is done through:

- pre-commit hooks
- flake checks
- manual verification that referenced commands and paths still exist

When changing architecture docs, confirm related module paths/options in `modules/`, `packages/`, or `scripts/` are still accurate.

## Commit & Pull Request Guidelines

Follow Conventional Commits, typically with a docs scope:

- `docs(architecture): clarify automatic module discovery`
- `chore(docs): normalize cloudflare command examples`

Keep each commit focused on one documentation concern. PRs should include:

- `## Summary`
- `## Test plan` (list commands run)
- linked issue/context when applicable

Do not include generated artifact edits unless they were intentionally regenerated as part of the same change.
