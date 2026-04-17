# GitHub Labels

This repository uses a faceted label taxonomy so labels answer one question at a time.

## Usage Rules

- Apply exactly one `type(...)` label.
- Apply at most one `status(...)` label.
- Apply at most one `priority(...)` label.
- Apply any relevant `area(...)` labels when they identify the affected subsystem.
- Apply `host(...)` only when the work is host-specific.
- Apply `focus(...)` only when the concern is cross-cutting and central to the work.
- Apply `origin(automated)` only to issues or pull requests created by bots or workflows.
- Use `type(docs)` for documentation-only work. Use `area(docs)` when code work also has significant documentation surface.

## Type Labels

| Label                     | Description                                                                                              |
| ------------------------- | -------------------------------------------------------------------------------------------------------- |
| `type(bug)`               | Use for a broken behavior or regression that needs fixing; not for questions or planned changes.         |
| `type(enhancement)`       | Use for net-new capability or an intentional improvement; not for refactors or routine bumps.            |
| `type(question)`          | Use when the issue is asking for clarification or design input; not for confirmed implementation work.   |
| `type(docs)`              | Use for documentation-only work or missing documentation; not for code changes that merely include docs. |
| `type(refactor)`          | Use for internal structural cleanup without intended behavior change; not for feature work.              |
| `type(migration)`         | Use for moving systems, data, ownership, or integrations across boundaries; not for local cleanup.       |
| `type(dependency-update)` | Use for dependency, flake input, or GitHub Action version bumps; not for broader feature work.           |

## Status Labels

| Label                      | Description                                                                                         |
| -------------------------- | --------------------------------------------------------------------------------------------------- |
| `status(backlog)`          | Use for accepted work that is intentionally unscheduled; not for items blocked externally.          |
| `status(blocked-upstream)` | Use when this repo cannot proceed until an upstream fix or release lands; not for reprioritization. |
| `status(in-progress)`      | Use for work actively being implemented; not for merely planned or queued work.                     |
| `status(duplicate)`        | Use when another issue or pull request already tracks the same work.                                |
| `status(invalid)`          | Use when the report is not actionable for this repo as filed.                                       |
| `status(wontfix)`          | Use when the work is understood but will not be pursued.                                            |

## Priority Labels

| Label          | Description                                                           |
| -------------- | --------------------------------------------------------------------- |
| `priority(p1)` | Use for critical work that blocks safe operation or urgent delivery.  |
| `priority(p2)` | Use for important work that should land soon but is not an emergency. |
| `priority(p3)` | Use for normal-priority work that can wait behind more urgent items.  |

## Area Labels

| Label                 | Description                                                                                                      |
| --------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `area(agents)`        | Use for Codex, Claude Code, agent wrappers, prompts, or agent-facing tooling.                                    |
| `area(automation)`    | Use for scheduled jobs, sync jobs, or workflow-driven operational behavior; not for bot origin.                  |
| `area(ci)`            | Use for GitHub Actions, checks, or CI/CD execution logic.                                                        |
| `area(cloudflare)`    | Use for Cloudflare services, APIs, deployments, or R2/Workers integrations.                                      |
| `area(docs)`          | Use when repository documentation is a significant affected surface; not for docs-only classification.           |
| `area(flake)`         | Use for flake topology, inputs, outputs, lockfile management, or Nix CLI integration.                            |
| `area(git)`           | Use for repository sync, Git workflows, credentials, branches, or version-control policy.                        |
| `area(hardware)`      | Use for hardware enablement, drivers, firmware, power, or device-specific behavior.                              |
| `area(home-manager)`  | Use for Home Manager modules, activation, or user-environment configuration.                                     |
| `area(hooks)`         | Use for pre-commit, pre-push, and other repository hook logic.                                                   |
| `area(mcp)`           | Use for Model Context Protocol servers, catalog entries, or transport integration.                               |
| `area(networking)`    | Use for networking services, DNS, VPN, SSH transport, or host connectivity.                                      |
| `area(nixos)`         | Use for NixOS modules, host configuration, services, or system-level declarative behavior; not module mechanics. |
| `area(module-system)` | Use for import-tree behavior, evaluation order, option wiring, or module composition mechanics.                  |
| `area(packages)`      | Use for package definitions, overrides, overlays, or package-source selection.                                   |
| `area(scripts)`       | Use for operational scripts and command-line automation helpers.                                                 |
| `area(sops)`          | Use for sops-nix secrets, encrypted files, key material, or secret rendering paths.                              |
| `area(storage)`       | Use for disks, filesystems, backups, mounts, or data-placement configuration.                                    |

## Host Labels

| Label            | Description                                                            |
| ---------------- | ---------------------------------------------------------------------- |
| `host(system76)` | Use for changes specific to the System76 host or its runtime contract. |
| `host(tpnix)`    | Use for changes specific to the `tpnix` host or its runtime contract.  |

## Focus Labels

| Label                   | Description                                                                                              |
| ----------------------- | -------------------------------------------------------------------------------------------------------- |
| `focus(security)`       | Use when the main concern is a concrete security risk, secret exposure, auth boundary, or vulnerability. |
| `focus(hardening)`      | Use for proactive attack-surface reduction or tighter defaults without a specific vulnerability.         |
| `focus(validation)`     | Use for build checks, assertions, verification flows, or validation-specific failures.                   |
| `focus(data-integrity)` | Use for sync correctness, conflict safety, durability, or integrity guarantees.                          |

## Origin Labels

| Label               | Description                                                                                               |
| ------------------- | --------------------------------------------------------------------------------------------------------- |
| `origin(automated)` | Use only for issues or pull requests created by bots or workflows; not for user-authored automation work. |
