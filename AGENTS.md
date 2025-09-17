# Repository Guidelines

## Project Structure & Module Organization
Flake-driven imports auto-load everything under `modules/`; group by domain (`desktop/`, `shell/`, `security/`) and prefix `_` to opt out. `modules/devshell.nix` carries shared tooling, while reference docs, CI flows, and host notes live in `docs/`, `.github/`, and `nixos_docs_md`. Stage upstream flakes in `inputs/`, helper scripts in `scripts/`, and never commit anything sensitive under `secrets/`.

## Build, Test & Development Commands
- `nix develop`: enter the pinned dev shell with formatters, language servers, and hooks.
- `nix fmt`: run treefmt (`nixfmt`, `shfmt`, `prettier`) across tracked sources.
- `nix develop -c pre-commit run --all-files`: execute formatting, lint, security, and flake checks; treat failures as blockers.
- `generation-manager score`: verify Dendritic Pattern compliance (target 90/90 before merging).
- `nix flake check --accept-flake-config`: confirm flake evaluation and repository invariants.

## Coding Style & Naming Conventions
Use 2-space indentation in Nix, rely on `inherit`, and merge attributes for clarity. Name modules and attributes with lowercase hyphenated identifiers, avoiding literal paths when flake inputs suffice. Wrap modules in functions only when extra arguments (such as `pkgs`) are required. Always format locally before pushing; hooks enforce a zero-warning policy.

## Testing Guidelines
Treat `nix develop -c pre-commit run --all-files` as the regression suite and rerun it after each change. Iterate until checks succeed, document manual verification in the PR, and record behaviour shifts in repo docs as needed.

## Commit & Pull Request Guidelines
Use Conventional Commits (e.g., `feat(modules): add sway tweaks`, `fix(shell): restore prompt`). Scope PRs to a single concern, update related docs alongside code, link issues with `Closes #id`, and include screenshots for UX-facing updates. Provide rationale and host impact so reviewers can reconcile changes quickly.

## Security & Configuration Tips
Avoid system-altering commands (`nixos-rebuild`, `nix build`, `generation-manager switch`, garbage collection) unless explicitly requested. Honour `nixConfig.abort-on-warn = true`; resolve warnings at the source. Prefer local references in `nixos_docs_md` before consulting external material, and remember experimental pipe operators are enabled in Nix expressions.

## Agent Interaction Protocol
Assume the user is `default_user` unless evidence contradicts it, and confirm identity when uncertain. Start every interaction with the single phrase “Remembering...” while querying relevant details from your memory (the knowledge graph). Track new facts about identity, behaviours, preferences, goals, and relationships as conversations progress. When new information appears, update memory by creating entities for recurring people, organisations, or events, linking them to existing entities, and recording the observations for future sessions.
