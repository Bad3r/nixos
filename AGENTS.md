# Repository Guidelines

## Project Structure & Module Organization

- `modules/` autoloads by domain; keep features in `modules/desktop/`, `modules/shell/`, `modules/security/`, and prefix directories with `_` to park unfinished work.
- Share tooling through `modules/devshell.nix`; contributor notes live in `docs/`, CI flows in `.github/`, and host-specific runbooks in `nixos_docs_md/`.
- Pin upstream flakes inside `inputs/`, store helper utilities in `scripts/`, and leave `secrets/` empty in git history.

## Build, Test & Development Commands

- `nix develop`: enter the pinned dev shell with language servers, formatters, and pre-commit hooks.
- `nix fmt`: run treefmt (nixfmt, shfmt, prettier) across tracked sources before committing.
- `nix develop -c pre-commit run --all-files`: execute formatting, lint, security, and flake checks; treat failures as blockers.
- `generation-manager score`: confirm Dendritic Pattern compliance; target 90/90 prior to merge.
- `nix flake check --accept-flake-config`: validate flake evaluation and repository invariants.

## Coding Style & Naming Conventions

- Use 2-space indentation in Nix, prefer `inherit` for attribute reuse, and merge attribute sets for clarity.
- Name modules and attributes with lowercase hyphenated identifiers (e.g. `desktop-portal`), leaning on flake inputs instead of literal paths.
- Let `nix fmt` resolve formatting disagreements; avoid hand-editing generated files.

## Testing Guidelines

- Treat `nix develop -c pre-commit run --all-files` as the regression suite and rerun it after each change.
- Document manual validation steps alongside code when behaviour changes, and update `nixos_docs_md/` if host procedures shift.
- Re-check `generation-manager score` when touching module logic that could alter compliance metrics.

## Commit & Pull Request Guidelines

- Follow Conventional Commits such as `feat(modules): add sway tweaks` or `fix(shell): restore prompt`.
- Keep PRs single-purpose, describe host impact, link issues with `Closes #id`, and refresh related docs or screenshots.
- Summarize verification steps in the PR body so reviewers can replay checks quickly.

## Security & Configuration Tips

- Avoid system-altering commands (`nixos-rebuild`, `nix build`, `generation-manager switch`, garbage collection) unless requested by repository owners.
- Honour `nixConfig.abort-on-warn = true` by resolving warnings at the source and consulting `nixos_docs_md/` before external resources.

## Agent Interaction Protocol

- Assume the operator is `default_user`; if uncertain, confirm identity before acting.
- Start every interaction with “Remembering...” while querying stored knowledge, and log new facts about people, preferences, and workflows in the knowledge graph.

## MCP Browser Tools

- `accounts_list`: List the available Cloudflare Browser accounts; call once before other actions to pick the right tenant.
- `set_active_account`: Point subsequent browser calls at the desired account by passing the `id` retrieved from `accounts_list`.
- `get_url_html_content`: Fetch the raw HTML for a URL when you need full markup for parsing or inspection.
- `get_url_markdown`: Convert a URL to simplified Markdown; use for quick readability or note-taking.
- `get_url_screenshot`: Capture a rendered PNG of the target page for visual confirmation or archival.

## DeepWiki Tools

- `read_wiki_structure`: List the DeepWiki table of contents for a repository, so you can spot relevant sections quickly before diving in.
- `read_wiki_contents`: Stream the full article text for a specific section slug when you need detailed background.
- `ask_question`: Pose natural-language questions against the repo’s knowledge base to get concise, cited summaries on demand.

## Context7 Tools

- `resolve-library-id`: Look up the Context7-compatible identifier for a package or product name; call this first unless the exact ID is already supplied.
- `get-library-docs`: Retrieve targeted documentation for a resolved library ID (optionally scoping by topic or token budget) to embed authoritative references in answers.
