# Repository Guidelines

## Project Structure & Module Organization

This file governs the `docs/` subtree. Keep documentation scoped to existing folders:

- `architecture/`: canonical design docs for module system and composition.
- `guides/`, `usage/`, `reference/`: task-oriented instructions and reference material.
- `nixos-manual/`: mirrored upstream NixOS manual sources.
- `technical-writing/`: style guidance for documentation structure,
  examples, review, and lifecycle.
- Host and domain folders (for example `cloudflare/`, `songbird/`,
  `duplicati/`, `mpv/`, `r2-cloud/`, `sops/`, `system76/`, `usbguard/`):
  host-specific and product-specific docs.

Prefer updating an existing page over adding a new one. Update `index.md` when
adding, removing, or moving documentation pages. Use clear, repo-relative links
(for example `../architecture/README.md`) and keep host/user assumptions aligned
to the per-host model under `modules/<host>/` and the `vx` user model. To
enumerate the active hosts, run
`nix eval --accept-flake-config --json "path:.#nixosConfigurations" --apply builtins.attrNames`.

Use lowercase directory names for provider and product folders. Cloudflare docs
belong under `cloudflare/`, including Containers material under
`cloudflare/containers/`; do not recreate case variants such as `CloudFlare/`.
The mirrored NixOS manual belongs under `docs/nixos-manual/`; do not recreate a
root-level `nixos-manual/` tree.

## Build, Test, and Development Commands

Run commands from the root of the checkout the work is in. The root `AGENTS.md`
branch workflow puts that in a linked worktree, so these carry the explicit
`path:.` installable; dropping it gives the primary-checkout form.

- `nix develop path:.`: enter the dev shell with formatter and validation tools.
- `nix run path:.#treefmt -- .`: apply repository formatting rules. `nix fmt`
  hardcodes the `.` installable in `lix/nix/fmt.cc`, so it cannot be pointed at
  a linked worktree; the formatter is also a package, and `-- <file>` gives a
  targeted run.
- `nix develop path:. -c pre-commit run --all-files --hook-stage manual`: run all hooks.
- `nix flake check path:. --accept-flake-config --no-build --offline`: validate flake/module health without building.
- `nix flake update --flake "path:$PWD"`: refresh `flake.lock`. Positional
  arguments are input names, so the flake goes in `--flake`, and the ref there
  must be absolute. This and `nix fmt` are the two commands a plain `path:.`
  does not fix; the root `AGENTS.md` and `CLAUDE.md` carry the mechanism.

Use `rg -C 5 'pattern' docs/` to find and update related content before writing new docs.

## Coding Style & Naming Conventions

Use concise Markdown with descriptive headings (`##`, `###`) and short paragraphs. Keep examples executable and explicit:

```bash
nix develop path:. -c pre-commit run --all-files --hook-stage manual
```

Prefer lowercase, hyphenated filenames (for example `module-discovery.md`). Use backticks for commands, paths, options, and identifiers.
Follow the local technical-writing guidance for new or substantially rewritten
pages, especially `technical-writing/drafting.md` and
`technical-writing/code-samples.md`.

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
