# Repository Guidelines

## Project Structure & Module Organization

Keep per-app modules in `modules/apps/`, one file per tool or curated toolchain exporting `flake.nixosModules.apps.<name>` plus any default bundles (e.g., `pc`, `workstation`). Domain folders such as `modules/networking/`, `modules/security/`, and `modules/cloudflare/` are reserved for higher-level features that compose multiple apps or adjust system options; avoid installing packages there directly. Stage unfinished work under directories prefixed with `_`. Share common tooling through `modules/devshell.nix`, capture contributor notes in `docs/`, store CI automation in `.github/`, maintain host runbooks in `nixos_docs_md/`, pin upstream flakes in `inputs/`, keep helper scripts in `scripts/`, and ensure `secrets/` stays empty in git history.

## Build, Test, and Development Commands

- `nix develop`: open the pinned dev shell with language servers, formatters, and repo hooks preloaded.
- `nix fmt`: run treefmt (nixfmt, shfmt, prettier) across tracked sources; run before commits.
- `nix develop -c pre-commit run --all-files`: execute the full lint, security, and flake suite; treat failures as blockers.
- `generation-manager score`: verify Dendritic Pattern compliance; aim for 90/90 prior to merge.
- `nix flake check --accept-flake-config`: confirm flake evaluation and invariants.

## Coding Style & Naming Conventions

Use 2-space indentation in Nix, rely on `inherit` for shared attributes, and merge attribute sets for clarity. Name modules and options with lowercase hyphenated identifiers (e.g., `desktop-portal`). Let `nix fmt` resolve formatting disagreements and avoid touching generated files by hand.

## Testing Guidelines

Treat `nix develop -c pre-commit run --all-files` as the regression suite and rerun it after every change. Document any manual validation alongside code updates, and refresh `nixos_docs_md/` when host procedures shift. Re-run `generation-manager score` whenever module logic might affect compliance metrics.

## Commit & Pull Request Guidelines

Follow Conventional Commits such as `feat(modules): add sway tweaks` or `fix(shell): restore prompt`. Keep PRs single-purpose, describe host impact, link issues with `Closes #id`, and attach relevant screenshots or logs. Summarize verification steps in the PR description so reviewers can replay checks quickly.

## Security & Configuration Tips

Avoid system-altering commands (`nixos-rebuild`, `nix build`, `generation-manager switch`, garbage collection) unless the repo owners request them. Honour `nixConfig.abort-on-warn = true` by resolving warnings at the source and consulting `nixos_docs_md/` before using external resources.

## Agent Interaction Protocol

Assume the operator is `default_user` unless told otherwise. Start every interaction with “Remembering...” while consulting stored knowledge, and log new facts about people, preferences, and workflows in the knowledge graph.
