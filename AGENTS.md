# Repository Guidelines

## Critical Rule

- Never run any build or system-modification commands. Do not invoke `nixos-rebuild`, `nix build`, `build.sh`, `generation-manager switch/rollback`, GC/optimise, or similar.
- After .nix changes, only run validation: `nix fmt`, `nix develop -c pre-commit run --all-files`, `generation-manager score`, and `nix flake check --accept-flake-config`. Report results only.

## Project Structure & Module Organization

- `flake.nix`: Flake entry; defines inputs and imports all modules via `import-tree`.
- `modules/`: NixOS/Home‑Manager modules grouped by domain (e.g., `desktop/`, `shell/`, `security/`). Files prefixed with `_` are ignored by auto‑import. Example: `modules/desktop/plasma.nix`.
- `modules/devshell.nix`: Dev tooling (treefmt, pre‑commit, LSP).
- `docs/`, `.github/`: Documentation and CI metadata. Local NixOS docs live in `nixos_docs_md/`.

## Development & Validation Commands

- `nix develop`: Enter the dev shell (formatter, LSP, hooks available).
- `nix fmt`: Format Nix/Shell/Markdown via treefmt.
- `nix develop -c pre-commit run --all-files`: Run all hooks (format, lint, security, flake checks).
- `generation-manager score`: Dendritic Pattern compliance (target: 90/90).
- `nix flake check --accept-flake-config`: Validate flake evaluation and invariants.

## Coding Style & Naming Conventions

- **Nix style**: 2‑space indent, prefer `inherit` and attribute merging over repetition.
- **Modules**: Lowercase, hyphenated filenames; one concern per file. Use `_prefix.nix` to exclude.
- **Formatting**: Always run `nix fmt` (treefmt‑nix: nixfmt, shfmt, prettier).
- **Options**: Keep option names descriptive; group by domain directory.
- **Imports**: No literal path imports; rely on namespace/flake inputs and auto‑import.
- **Functions**: Wrap modules in a function only when `pkgs` is required.

## Testing Guidelines

- **Format & hooks**: `nix fmt` then `nix develop -c pre-commit run --all-files` must pass cleanly.
- **Pattern score**: `generation-manager score` should report 90/90.
- **Flake check**: `nix flake check --accept-flake-config` from repo root.
- Never run any build/switch/GC commands in tests.

## Commit & Pull Request Guidelines

- **Conventional Commits**: `feat(scope): summary`, `fix(style): ...`, `chore(dev): ...`, `docs(...): ...` (see `git log`).
- **PRs must include**: clear description, affected hosts/modules, rationale, and `Closes #<id>` when applicable. Add screenshots for UX/UI changes.
- **Scope small**: Prefer focused PRs; avoid unrelated refactors.

## Security & Configuration Tips

- Treat warnings as errors: `nixConfig.abort-on-warn = true` (keep builds clean).
- Use local docs first: search `nixos_docs_md/` before going online.
- Experimental features: pipe operators are enabled and expected in this repo.
- Do not invoke `build.sh` or any system-changing command.
