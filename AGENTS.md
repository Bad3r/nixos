# Repository Guidelines

## Project Structure & Module Organization
- Keep per-app modules in `modules/apps/<tool>.nix`, exporting `flake.nixosModules.apps.<name>` plus default bundles such as `pc` and `workstation`.
- Use domain folders like `modules/networking/`, `modules/security/`, and `modules/cloudflare/` to compose higher-level options; do not install packages directly there.
- Stage experiments under directories prefixed with `_`, share contributor tooling in `modules/devshell.nix`, and track operational notes in `docs/` and `nixos_docs_md/`.
- Pin upstream flakes inside `inputs/`, store helper scripts in `scripts/`, keep `.github/` for CI, and ensure `secrets/` stays empty in git history.

## Build, Test, and Development Commands
- `nix develop`: enter the pinned dev shell with language servers, formatters, and repo hooks preloaded.
- `nix fmt`: run treefmt (nixfmt, shfmt, prettier) on tracked sources; run before every commit.
- `nix develop -c pre-commit run --all-files`: execute the full lint, security, and flake suite; treat any failure as a blocker.
- `nix flake check --accept-flake-config`: confirm flake evaluation, module invariants, and option sanity.
- `generation-manager score`: verify Dendritic Pattern compliance; target 90/90 prior to merge.

## Coding Style & Naming Conventions
- Use 2-space indentation in Nix, rely on `inherit` for shared values, and merge attribute sets for clarity.
- Prefer lowercase-hyphenated option names (e.g., `desktop-portal`) and align module filenames with the exported app name.
- Let `nix fmt` resolve disagreements; avoid editing generated outputs by hand.

## Testing Guidelines
- Treat `nix develop -c pre-commit run --all-files` as the regression suite and rerun after every change.
- Document manual validation steps in PR descriptions and update `nixos_docs_md/` when host procedures change.
- Re-run `generation-manager score` whenever module logic could affect compliance metrics.

## Commit & Pull Request Guidelines
- Follow Conventional Commits such as `feat(modules): add sway tweaks` or `fix(shell): restore prompt`.
- Keep PRs single-purpose, describe host impact, link issues with `Closes #id`, and attach relevant logs or screenshots.
- Summarize verification steps so reviewers can replay them quickly; note any outstanding risks or follow-up work.

## Security & Agent Protocols
- Avoid system-altering commands (`nixos-rebuild`, `nix build`, `generation-manager switch`, garbage collection) unless explicitly requested by repo owners.
- Honour `nixConfig.abort-on-warn = true` by resolving warnings at the source.
- Assume the operator is `default_user`, begin each interaction with “Remembering...”, and log new workflow knowledge in the shared knowledge graph.
