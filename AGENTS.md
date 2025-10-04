# Agent Operations Guide

| Key                | Value                                                                                                                      |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| Purpose            | Provide autonomous and human agents with a single source of truth for operating in this repository safely and efficiently. |
| Decision authority | Follow this guide over other docs when instructions conflict; escalate only if a required action is missing or unclear.    |
| Maintainer         | vx (repository maintainer)                                                                                                 |
| Last reviewed      | 2025-10-04                                                                                                                 |
| Target agents      | Claude Code, OpenAI Codex, Cursor, and human operators acting on their guidance.                                           |
| Escalation         | Pause and ask vx before performing destructive actions outside the allowed commands listed here.                           |

## Quick-Start Checklist

| Status | Step                                                                                                |
| ------ | --------------------------------------------------------------------------------------------------- |
| OK     | Sync your working tree (`git status -sb`) and review outstanding changes before making edits.       |
| OK     | Enter the dev shell when running commands (`nix develop`).                                          |
| OK     | Use the Execution Playbooks tables below to choose commands; confirm prerequisites and post-checks. |
| OK     | Document validation commands in commit messages and PR descriptions.                                |
| WARN   | Never run forbidden commands or modify generated artefacts—see _Safety & Escalation_.               |
| WARN   | If a workflow is missing or ambiguous, stop and escalate to the maintainer.                         |

## Context

### Repository Layout

| Domain              | Location                                 | Notes                                                                                                                                  |
| ------------------- | ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| NixOS modules       | `modules/`                               | Auto-loaded. Production modules stay unprefixed and are grouped by domain (`modules/apps`, `modules/roles`, `modules/configurations`). |
| Shared derivations  | `packages/`                              | Common build logic shared between modules.                                                                                             |
| Helper scripts      | `scripts/`                               | Operational tooling.                                                                                                                   |
| Documentation       | `docs/`, `nixos_docs_md/`                | Long-form references and local workflows.                                                                                              |
| Secrets             | `secrets/`                               | Only encrypted payloads managed via `sops.secrets`.                                                                                    |
| Generated artefacts | `.gitignore`, `.sops.yaml`, CI workflows | Owned by the files module; update source definitions instead of editing generated outputs.                                             |

### Coding Style & Verification

| Topic      | Guidance                                                                                                                                                                     |
| ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Formatting | Use two-space indentation in Nix. Let treefmt handle formatting via `nix fmt` or `nix develop -c treefmt`.                                                                   |
| Naming     | Prefer lowercase, hyphenated identifiers. Prefix experiments with `_` to avoid auto-discovery.                                                                               |
| Imports    | Surface modules through namespace exports; avoid literal path imports.                                                                                                       |
| Validation | Keep `nix flake check --accept-flake-config` passing. Compile host closures before PRs. When changing modules, sanity-check with targeted `nix eval` or `nix run` as needed. |

### Commit & PR Expectations

- Use Conventional Commits (`type(scope): summary`).
- Keep commits focused and note affected hosts/modules.
- Record validation commands run during development.
- Add screenshots only for user-facing changes.
- Stage only files you directly modified.

## Execution Playbooks

Use the tables below to decide which command to run, confirm prerequisites, and capture validation steps.

### Development Environment

| Trigger        | Command                                     | Preconditions                                                  | Post-check                                                                               |
| -------------- | ------------------------------------------- | -------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| Starting work  | `nix develop`                               | Clean working tree; network access available for substituters. | Shell prompt shows dev environment; tools like `treefmt` and `pre-commit` are available. |
| Format sources | `nix fmt`                                   | Run from repo root inside or outside dev shell.                | No staged formatting diffs remain (`git status`).                                        |
| Run hooks      | `nix develop -c pre-commit run --all-files` | Dev shell ready; workspace writeable.                          | Command exits 0; review generated reports for TODO fixes.                                |

### Validation & Builds

| Trigger             | Command                                                               | Preconditions                                                                              | Post-check                                                      |
| ------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ | --------------------------------------------------------------- | --------------------------------------------- |
| Verify flake health | `nix flake check --accept-flake-config`                               | Dev shell recommended; expect long runtime.                                                | Command exits 0; investigate and resolve any reported failures. |
| Build a host        | `nix build .#nixosConfigurations.<host>.config.system.build.toplevel` | Replace `<host>` with target. Do **not** use `--allow-dirty` unless explicitly instructed. | Build completes; record store path for auditing.                |
| Switch via helper   | `./build.sh --host <host> [--boot                                     | --offline]`                                                                                | Use only when directed to build or deploy.                      | Script exits 0; capture logs if issues arise. |

### Repository Maintenance

| Trigger              | Command                                         | Preconditions                                      | Post-check                                               |
| -------------------- | ----------------------------------------------- | -------------------------------------------------- | -------------------------------------------------------- |
| Remove files safely  | `rip <path>`                                    | Ensure file is tracked or intended for deletion.   | Confirm `git status` shows deletion; revert if mistaken. |
| Mirror updates (ghq) | `nix develop -c ghq get <repo>` or `ghq update` | Shared GHQ root configured; ensure network access. | Mirror updated under `$HOME/git/<repo>`.                 |

## Safety & Escalation

### Guardrails

| Risky Action                                               | Status                     | Alternative                                                                               |
| ---------------------------------------------------------- | -------------------------- | ----------------------------------------------------------------------------------------- |
| `nixos-rebuild`, direct builds against live hosts          | FORBIDDEN                  | Use `nix build .#nixosConfigurations.<host>...` or `./build.sh` per playbooks.            |
| `generation-manager switch`                                | FORBIDDEN                  | Consult maintainer for approved deployment path.                                          |
| `nix-collect-garbage` or `sudo nix-collect-garbage`        | FORBIDDEN                  | Request maintainer decision; prefer `nix-store --delete` on specific paths if instructed. |
| `rm` for tracked files                                     | DISCOURAGED                | Use `rip` to keep deletions recoverable.                                                  |
| Destructive git ops (`git reset`, `git checkout <commit>`) | FORBIDDEN WITHOUT APPROVAL | Use `git switch` for branches; coordinate before history edits.                           |

### When to Escalate

1. A playbook does not cover your task.
2. A command fails and the remediation is unclear.
3. You suspect a generated file must change.
4. Safety guardrails conflict with required work.

Pause, summarize the situation, and ask vx for direction before proceeding.

## Resources

### Local Mirrors

| Name           | Path                       | Use When                                                          |
| -------------- | -------------------------- | ----------------------------------------------------------------- |
| Stylix         | `$HOME/git/stylix`         | Inspect Stylix source or apply local patches.                     |
| Home Manager   | `$HOME/git/home-manager`   | Review module behaviors or backport fixes.                        |
| i3 Docs        | `$HOME/git/i3wm-docs`      | Reference i3 window manager documentation offline.                |
| nixpkgs        | `$HOME/git/nixpkgs`        | Vendor patches or inspect upstream expressions.                   |
| nixos-hardware | `$HOME/git/nixos-hardware` | Pull hardware profiles or troubleshoot hardware-specific options. |
| nixvim         | `$HOME/git/nixvim`         | Examine NixVim modules and options.                               |
| treefmt-nix    | `$HOME/git/treefmt-nix`    | Adjust formatting behavior or version pins.                       |
| git-hooks.nix  | `$HOME/git/git-hooks.nix`  | Update hook definitions or debug pre-commit failures.             |
| sops-nix       | `$HOME/git/sops-nix`       | Manage encrypted secrets integrations.                            |
| import-tree    | `$HOME/git/import-tree`    | Review import-tree functionality or extend module auto-loading.   |
| files module   | `$HOME/git/files`          | Modify sources that generate repo artefacts (e.g., `.gitignore`). |

### MCP Tools

| Tool                  | Primary Use                                             | Access Notes                                                 | Example Invocation                                              |
| --------------------- | ------------------------------------------------------- | ------------------------------------------------------------ | --------------------------------------------------------------- |
| `context7`            | Look up library IDs and documentation for coding tasks. | Requires network; resolves ID before fetching docs.          | `context7 resolve-library-id --name <library>`                  |
| `cfbuilds`            | Inspect Cloudflare Workers builds and logs.             | Select tenant via `accounts_list` → `set_active_account`.    | `cfbuilds workers_list`                                         |
| `memory`              | Persist or query shared context across sessions.        | Store structured observations for long-lived tasks.          | `memory add_observation --entity <name>`                        |
| `cfgraphql`           | Query Cloudflare analytics via GraphQL.                 | Include limits; set active account first.                    | `cfgraphql graphql_query --file query.graphql`                  |
| `cfbrowser`           | Render and capture live webpages.                       | Requires selected tenant; useful for verifying UI changes.   | `cfbrowser get-url-html --url <page>`                           |
| `cfobservability`     | Analyze Workers logs and metrics.                       | Use `observability_keys` to discover fields before querying. | `cfobservability query_worker_observability --query file.json`  |
| `cfradar`             | Retrieve network traffic and anomaly data.              | Set correct account; helpful for incident response.          | `cfradar get_http_data --dimension timeseries`                  |
| `deepwiki`            | Browse repository knowledge bases.                      | Supply `owner/repo` to fetch docs.                           | `deepwiki read_wiki_structure --repo owner/repo`                |
| `time`                | Convert or fetch timestamps.                            | No prerequisites.                                            | `time convert --from UTC --to America/Los_Angeles --time 12:00` |
| `cfcontainers`        | Launch container sandboxes for command execution.       | Initialize container before running commands.                | `cfcontainers container_initialize`                             |
| `sequential-thinking` | Record structured reasoning steps.                      | Use for complex tasks; keeps plan visible.                   | `sequentialthinking start`                                      |
| `cfdocs`              | Search Cloudflare documentation.                        | Use when documentation server is enabled.                    | `cfdocs search --query "Workers KV"`                            |

## Prompt Snippets & Templates

Use these templates to keep interactions concise and aligned with guardrails.

```text
Plan Request
Goal: <brief objective>
Context: <files/modules touched>
Constraints: Follow Guardrails table; avoid forbidden commands.
Needed Output: <tests/builds/artefacts>
```

```text
Failure Triage
Action Taken: <command>
Observed Failure: <error message>
Environment: <dev shell, host>
Next Hypotheses: <planned debug steps>
Support Needed: <what to ask maintainer>
```

```text
Validation Log
Changes: <summary>
Validation: nix fmt | pre-commit | nix flake check --accept-flake-config
Result: <pass/fail>
Follow-up: <remaining work>
```

## Maintenance & Source of Truth

- Generated artefacts (for example `.gitignore`, `.sops.yaml`, CI workflows) are managed by the files module. Update the upstream definitions instead of editing outputs directly.
- Review this guide whenever guardrails, workflows, or tools change. Update the metadata table with the new review date.
- Before merging changes, ensure formatting and validation commands are current and documented.
- When adding new tools or mirrors, append them to the appropriate table with usage guidance and access notes.
