# Repository Guidelines

## Project Structure & Module Organization

- `flake.nix`: Flake entry; defines inputs and auto‑imports modules via `import-tree`.
- `modules/`: NixOS/Home‑Manager modules by domain (`desktop/`, `shell/`, `security/`). Files prefixed with `_` are ignored. Example: `modules/window-manager/i3.nix`.
- `modules/devshell.nix`: Dev tooling (treefmt, pre‑commit, LSP).
- `docs/`, `.github/`, `nixos_docs_md/`: Documentation, CI, and local NixOS notes.

## Development & Validation Commands

- `nix develop`: Dev shell with formatter, LSP, hooks.
- `nix fmt`: Format Nix/Shell/Markdown via treefmt.
- `nix develop -c pre-commit run --all-files`: Run all hooks (format, lint, security, flake checks).
- `generation-manager score`: Dendritic Pattern compliance (target 90/90).
- `nix flake check --accept-flake-config`: Validate flake evaluation/invariants.

## Coding Style & Naming Conventions

- Nix: 2‑space indent; prefer `inherit` and attribute merging.
- Modules: lowercase, hyphenated; one concern per file; use `_prefix.nix` to exclude.
- Imports: no literal paths; rely on flake inputs + auto‑import.
- Functions: wrap a module only when `pkgs` is required.
- Formatting: treefmt‑nix (`nixfmt`, `shfmt`, `prettier`). Ensure `nix fmt` and pre‑commit hooks pass before commit.

## Testing Guidelines

- Treat warnings as errors; hooks must pass cleanly.
- Run the validation commands above from repo root; target 90/90 score.
- Follow the Safety rule in Security & Configuration Tips.

## Commit & Pull Request Guidelines

- Conventional Commits: `feat(scope): summary`, `fix(style): …`, `chore(dev): …`, `docs(...): …`.
- PRs include description, affected hosts/modules, rationale, and `Closes #<id>`; add screenshots for UX/UI changes.
- Keep scope small; avoid unrelated refactors.

## Security & Configuration Tips

- Never run system‑modifying commands: `nixos-rebuild`, `nix build`, `build.sh`, `generation-manager switch/rollback`, GC/optimize.
- `nixConfig.abort-on-warn = true`.
- Prefer local docs in `nixos_docs_md/` before going online.
- Experimental features enabled: pipe operators.
