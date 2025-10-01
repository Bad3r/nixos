# Repository Guidelines

## Project Structure & Module Organization

Modules auto-load from `modules/`; keep production files unprefixed and group by domain (`modules/apps` for app bundles, `modules/roles` for host roles, `modules/configurations` for entrypoints). Shared derivations live in `packages/`, helper scripts in `scripts/`, and long-form docs in `docs/` or `nixos_docs_md/`. Only store encrypted payloads under `secrets/` and declare them via `sops.secrets`. Generated artefacts such as `.gitignore`, `.sops.yaml`, and CI workflows are owned by the files module—update source definitions instead of editing outputs.

## Build, Test, and Development Commands

- `nix develop` — enter the pinned dev shell with treefmt, pre-commit, and helper utilities.
- `nix fmt` — run treefmt (nixfmt, shfmt, prettier) across tracked sources.
- `nix develop -c pre-commit run --all-files` — execute the hook suite; treat failures as blocking.
- `nix flake check --accept-flake-config` — validate option schemas, overlays, packages, and tests.
- `nix build .#nixosConfigurations.<host>.config.system.build.toplevel` or `./build.sh --host <host> [--boot|--offline]` — build/switch target systems; reserve `--allow-dirty` for emergencies.

## Coding Style & Verification

Use two-space indentation in Nix, prefer lowercase hyphenated identifiers, and surface modules through namespace exports rather than literal path imports. Prefix experiments with `_` to skip auto-discovery. Let treefmt manage formatting and avoid modifying generated files by hand. Keep `nix flake check` green, compile host closures before PRs, sanity-check module changes with targeted `nix eval` or `nix run`, and document any manual validation directly in the PR description.

## Commit & PR Guidelines

Follow Conventional Commits (`type(scope): summary`) as in current history. Keep commits focused, note affected hosts/modules, list validation commands, and add screenshots only for user-facing changes. Link issues or TODO follow-ups and request review from maintainers owning the touched namespace.

## Security, Operations & Forbidden Commands

Encrypt secrets with sops-nix and update `.sops.yaml` via its source definition. Never commit decrypted material. Unless explicitly requested by an owner, do _not_ run `nixos-rebuild`, `nix build` against live hosts, `generation-manager switch`, `nix-collect-garbage`, or `sudo nix-collect-garbage`. Honour `nixConfig.abort-on-warn = true` by fixing warnings at the source.

## Local Upstream Mirrors

- Stylix source checkout is available at `$HOME/git/stylix`.
- Home Manager source checkout is available at `$HOME/git/home-manager`.
- i3 window manager documentation checkout is available at `$HOME/git/i3wm-docs`.
- nixpkgs mirror is available at `$HOME/git/nixpkgs`.
- nixos-hardware mirror is available at `$HOME/git/nixos-hardware`.
- nixvim mirror is available at `$HOME/git/nixvim`.
- treefmt-nix mirror is available at `$HOME/git/treefmt-nix`.
- git-hooks.nix mirror is available at `$HOME/git/git-hooks.nix`.
- sops-nix mirror is available at `$HOME/git/sops-nix`.
- import-tree mirror is available at `$HOME/git/import-tree`.
- files module source is available at `$HOME/git/files`.

New mirrors can be added under `$HOME/git` whenever pulling upstream source locally will speed up fixes or debugging.

## MCP Tool Reference

- **context7** — Resolve library identifiers and pull up-to-date docs/snippets for code questions; call `resolve-library-id` before `get-library-docs` unless you already know the Context7 path. citeturn0search1
- **cfbuilds** — Surface Worker build inventory and logs via Workers Builds tools (`workers_list`, `workers_builds_list_builds`, `workers_builds_get_build`, `workers_builds_get_build_logs`, `workers_builds_set_active_worker`) after picking the tenant with `accounts_list`/`set_active_account`. citeturn17search1
- **memory** — Maintain shared context with CRUD tools (`create_entities`, `add_observations`, `create_relations`, and matching delete/search operations); use it to persist project facts between sessions.
- **cfgraphql** — Query Cloudflare analytics through the GraphQL API; enumerate accounts with `accounts_list`, inspect schema with `graphql_schema_overview/search/type_details`, and run scoped requests via `graphql_query` while keeping `set_active_account` aligned. citeturn17search1
- **cfbrowser** — Fetch rendered pages, Markdown, or screenshots through Browser Rendering when a tenant is selected (`accounts_list` → `set_active_account`), enabling agents to review live web content. citeturn19view0
- **cfobservability** — Explore Workers logs with `observability_keys`, `observability_values`, and `query_worker_observability`, supplementing code changes with real invocation evidence. citeturn19view0
- **cfradar** — Answer traffic, AS, and anomaly questions using Radar datasets (`get_http_data`, `get_domains_ranking`, `get_traffic_anomalies`, etc.) after selecting the correct account. citeturn19view0
- **deepwiki** — Navigate repository knowledge bases via `read_wiki_structure`, `read_wiki_contents`, and `ask_question` for cited summaries.
- **time** — Convert or fetch timestamps (`convert_time`, `get_current_time`) to coordinate changes or maintenance windows across time zones.
- **cfcontainers** — Spin up Cloudflare container sandboxes for command execution or file edits with `container_initialize`, `container_exec`, and companion file operations. citeturn19view0
- **sequential-thinking** — Capture structured, multi-step reasoning traces with `sequentialthinking`; use it to log plan/critique cycles in long tasks.
- **cfdocs** — Search Cloudflare documentation on demand when the Documentation server is enabled; combine `search_cloudflare_documentation` with workflow-specific follow-ups like `migrate_pages_to_workers_guide`. citeturn19view0
