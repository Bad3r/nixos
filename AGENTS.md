# Repository Guidelines

## Project Structure & Module Organization
- `flake.nix` orchestrates inputs and auto-imports modules via `import-tree`; keep new modules under `modules/`.
- `modules/` holds NixOS/Home-Manager modules grouped by domain (e.g., `desktop/`, `shell/`, `security/`); prefix filenames with `_` to disable auto-imports and keep one concern per file.
- `modules/devshell.nix` provisions the dev shell, treefmt, pre-commit hooks, and language servers.
- `docs/`, `.github/`, and `nixos_docs_md/` store reference docs, CI workflows, and host-specific notes.
- `inputs/`, `scripts/`, and `secrets/` capture upstream flakes, helper scripts, and sensitive material (leave `secrets/` to repository owners).

## Build, Test & Development Commands
- `nix develop`: enter the dev environment with formatter, LSP, and hooks.
- `nix fmt`: run treefmt (`nixfmt`, `shfmt`, `prettier`) over tracked sources.
- `nix develop -c pre-commit run --all-files`: execute formatting, lint, security, and flake checks; treat failures as blockers.
- `generation-manager score`: measure Dendritic Pattern compliance (target 90/90).
- `nix flake check --accept-flake-config`: validate flake evaluation and repository invariants.

## Coding Style & Naming Conventions
- Use 2-space indentation in Nix; prefer `inherit` and attribute merging for clarity.
- Name modules and attributes in lowercase with hyphens; avoid literal paths and rely on flake-provided imports.
- Wrap modules in functions only when `pkgs` or other arguments are needed.
- Format locally before committing; hooks enforce a zero-warning policy.

## Testing Guidelines
- Rely on flake checks, pre-commit hooks, and `generation-manager score` for regression coverage.
- Run validation commands from the repo root after each change; iterate until results are clean.
- Document manual verification steps in PRs whenever behaviour or UX changes.

## Commit & Pull Request Guidelines
- Follow Conventional Commits (`feat(scope): message`, `fix(style): message`, `docs(...): message`, etc.).
- Keep PRs focused on a single concern; update related documentation alongside code.
- Provide rationale, impacted hosts/modules, linked issues (`Closes #id`), and screenshots for UX-facing updates.

## Security & Configuration Tips
- Avoid system-altering commands (`nixos-rebuild`, `nix build`, `generation-manager switch`, garbage collection) unless instructed.
- Honour `nixConfig.abort-on-warn = true`; resolve warnings instead of suppressing them.
- Prefer local references in `nixos_docs_md/` before seeking external sources; note that experimental pipe operators are enabled.
