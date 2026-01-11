# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **IMPORTANT:** This repo manages a single System76 host with the sole user `vx`. Do not introduce additional hosts or users—none will ever be added.

> **IMPORTANT:** Never consider backward compatibility. Eliminate legacy support by default.

## 🚨 CRITICAL SAFETY RULES - READ FIRST

These rules override ALL other instructions. Violating these rules is **UNACCEPTABLE**.

### Rule #1: NEVER Make Changes Irrecoverable

**ABSOLUTELY FORBIDDEN:**

- `git stash drop` or `git stash clear` - NEVER delete stashes
- `git reset --hard` without explicit user approval
- `git clean -fd` or similar destructive operations
- `rm -rf` on user files or directories
- Any command that permanently deletes user work

**REQUIRED PRACTICES:**

- Use `rip <path>` instead of `rm` for file deletions (recoverable from graveyard)
- Use `git stash` to save work, but **NEVER** drop stashes
- If you need to temporarily move files aside, use `git stash` and **LEAVE THEM STASHED**
- Always preserve user changes - if uncertain, ask first
- Before any potentially destructive operation, **STOP AND ASK THE USER**

**IF YOU ACCIDENTALLY DELETE SOMETHING:**

1. **IMMEDIATELY** attempt recovery (e.g., from stash hash, reflog, rip graveyard)
2. **INFORM THE USER** of what happened and what you recovered
3. **NEVER** hide or minimize deletion mistakes

### Rule #2: Git Stash Operations

**ALLOWED:**

- `git stash` - Save uncommitted changes
- `git stash list` - List stashes
- `git stash show` - View stash contents
- `git stash pop` - Apply and remove stash (only with user approval)
- `git stash apply` - Apply stash without removing it

**FORBIDDEN:**

- `git stash drop` - NEVER delete stashes
- `git stash clear` - NEVER delete all stashes

**PREFERRED ALTERNATIVE:**
Use `rip` command for temporary file removal instead of stashing when possible.

## Repository Overview

This is a NixOS configuration using the **Dendritic Pattern** - an organic configuration growth pattern with automatic module discovery. Files can be moved and nested freely without breaking imports.

> **Canonical Documentation:** See [`docs/architecture/`](docs/architecture/) for the complete architecture reference, including pattern overview, module authoring, aggregators, and host composition.

## Nix Configuration

This flake enforces strict evaluation and build settings:

| Setting                        | Value                  | Purpose                                                           |
| ------------------------------ | ---------------------- | ----------------------------------------------------------------- |
| `abort-on-warn`                | `true`                 | Treat warnings as errors to maintain code quality                 |
| `extra-experimental-features`  | `[ "pipe-operators" ]` | Enable pipe operator syntax in Nix expressions                    |
| `allow-import-from-derivation` | `false`                | Prevent IFD to ensure evaluation purity and build reproducibility |
| `experimental-features`        | `nix-command flakes`   | Enable flakes and new Nix CLI                                     |

These settings are mirrored in `build.sh` via `NIX_CONFIGURATION` environment variable.

## Quick-Start Checklist

| Status | Step                                                                                                |
| ------ | --------------------------------------------------------------------------------------------------- |
| OK     | Sync your working tree (`git status -sb`) and review outstanding changes before making edits.       |
| OK     | Enter the dev shell when running commands (`nix develop`).                                          |
| OK     | Use the Execution Playbooks tables below to choose commands; confirm prerequisites and post-checks. |
| OK     | Document validation commands in commit messages and PR descriptions.                                |
| WARN   | Never run forbidden commands or modify generated artefacts—see _Safety & Escalation_.               |
| WARN   | If a workflow is missing or ambiguous, stop and escalate to the maintainer.                         |

## Architecture & Module System

### Automatic Module Discovery

All Nix files are automatically imported as flake-parts modules. Files prefixed with `_` are ignored. No literal path imports are used - modules register themselves under namespaces:

- `flake.nixosModules`: NixOS modules (freeform, nested namespaces)
- `flake.homeManagerModules`: Home Manager modules (base, gui, per-app under `apps`)

### Module Composition Pattern

Hosts compose modules by importing from aggregator namespaces rather than literal paths. See [`docs/architecture/02-module-authoring.md`](docs/architecture/02-module-authoring.md) for patterns and [`docs/architecture/05-host-composition.md`](docs/architecture/05-host-composition.md) for host definitions.

Use `lib.hasAttrByPath` + `lib.getAttrFromPath` for optional modules to avoid ordering issues.

### Flake Input Deduplication

Inputs prefixed with `dedupe_` exist solely for dependency deduplication via `.follows` declarations. These inputs are grouped in a separate `inputs` attribute in `flake.nix` for easy identification. If all `follows` targeting a dedupe input are removed, the dedupe input should also be removed.

Example:

```nix
dedupe_systems.url = "github:nix-systems/default";
# Referenced by: stylix.inputs.systems.follows, sink-rotate.inputs.systems.follows
```

### Repository Layout

| Domain              | Location                                          | Notes                                                                                                                                                                    |
| ------------------- | ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| NixOS modules       | `modules/`                                        | Auto-loaded. Host-specific logic lives under `modules/system76`, while shared bundles remain organized by domain (for example `modules/apps`, `modules/configurations`). |
| Shared derivations  | `packages/`                                       | Common build logic shared between modules.                                                                                                                               |
| Helper scripts      | `scripts/`                                        | Operational tooling including git-credential-sops.                                                                                                                       |
| Documentation       | `docs/`, `nixos-manual/`                          | Long-form references and local workflows.                                                                                                                                |
| Secrets             | `secrets/`                                        | Only encrypted payloads managed via `sops.secrets`.                                                                                                                      |
| Generated artefacts | `.actrc`, `.gitignore`, `.sops.yaml`, `README.md` | Owned by the files module; update source definitions instead of editing generated outputs.                                                                               |

### Module Authoring Guidelines

All application modules in `modules/apps/` **MUST** follow the NixOS module best practices pattern:

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.<package-name>.extended;
  <PackageName>Module = {
    options.programs.<package-name>.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;  # Explicit opt-in required
        description = "Whether to enable <package-name>.";
      };

      package = lib.mkPackageOption pkgs "<package-name>" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.<package-name> = <PackageName>Module;
}
```

**Key Requirements**:

- ✅ Use `options.programs.<name>.extended` namespace
- ✅ Include `enable` option with `mkOption` (not `mkEnableOption` to preserve `default = true`)
- ✅ Include `package` option using `mkPackageOption` for customization
- ✅ Wrap config in `lib.mkIf cfg.enable` block
- ✅ Export via `flake.nixosModules.apps.<name>`

**Reference Implementations**:

- Simple application: `modules/apps/firefox.nix`, `modules/apps/wget.nix`
- Unfree application: `modules/apps/brave.nix`
- Complex with options: `modules/apps/steam.nix`, `modules/apps/mangohud.nix`

**Module Standards**:

All app modules follow standardized NixOS patterns with:

- Proper `options.programs.<name>.extended` namespace
- Explicit opt-in via `enable` option (default = false)
- Package customization via `mkPackageOption`
- Conditional configuration with `lib.mkIf`

## Execution Playbooks

### Branch Workflow

**Rule:** All changes require a dedicated worktree and PR. Never commit directly to main unless the user explicitly approves.

| Step   | Command                                                             |
| ------ | ------------------------------------------------------------------- |
| Create | `git worktree add $HOME/trees/nixos/<type>-<name> -b <type>/<name>` |
| Work   | `cd $HOME/trees/nixos/<type>-<name>` then commit changes            |
| PR     | `gh pr create --title "<type>(scope): summary" --body "..."`        |

Branch `<type>` uses Conventional Commits prefixes (see _Commit & PR Expectations_).

**PR body:**

- `## Summary` — what changed and why
- `## Test plan` — validation commands run (per existing "Record validation commands" guideline)

### Development Environment

| Trigger            | Command                                     | Preconditions                                                  | Post-check                                                                               |
| ------------------ | ------------------------------------------- | -------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| Starting work      | `nix develop`                               | Clean working tree; network access available for substituters. | Shell prompt shows dev environment; tools like `treefmt` and `pre-commit` are available. |
| Format sources     | `nix fmt`                                   | Run from repo root inside or outside dev shell.                | No staged formatting diffs remain (`git status`).                                        |
| Run hooks          | `nix develop -c pre-commit run --all-files` | Dev shell ready; workspace writeable.                          | Command exits 0; review generated reports for TODO fixes.                                |
| Generate artefacts | `nix develop -c write-files`                | Dev shell ready; updates managed files.                        | Check git diff for changes to `.actrc`, `.gitignore`, `.sops.yaml`, `README.md`.         |

### Validation & Builds

| Trigger             | Command                                                               | Preconditions                                                                              | Post-check                                                      |
| ------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ | --------------------------------------------------------------- |
| Verify flake health | `nix flake check --accept-flake-config --no-build --offline`          | Dev shell recommended; expect long runtime.                                                | Command exits 0; investigate and resolve any reported failures. |
| Build a host        | `nix build .#nixosConfigurations.<host>.config.system.build.toplevel` | Replace `<host>` with target. Do **not** use `--allow-dirty` unless explicitly instructed. | Build completes; record store path for auditing.                |
| Validate and deploy | `./build.sh [OPTIONS]`                                                | Clean working tree required unless `--allow-dirty` used.                                   | Script exits 0; capture logs if issues arise.                   |
| Update flake inputs | `./build.sh --update`                                                 | Clean working tree recommended.                                                            | Review updated lock file changes.                               |

#### build.sh Options

The `build.sh` script performs full validation (format, hooks, flake check) before deployment:

| Flag            | Purpose                                    | Use When                                            |
| --------------- | ------------------------------------------ | --------------------------------------------------- |
| `--host <name>` | Target specific hostname                   | Deploying to non-current host                       |
| `--boot`        | Install for next boot (don't activate now) | Testing changes before activation                   |
| `--offline`     | Build without network access               | Working offline or testing substituter independence |
| `--allow-dirty` | Override clean git tree requirement        | Emergency fixes; prefer clean commits               |
| `--update`      | Run `nix flake update` before building     | Updating all inputs to latest versions              |
| `--skip-fmt`    | Skip formatting step                       | Debugging when format is known-good                 |
| `--skip-hooks`  | Skip pre-commit hooks                      | Debugging when hooks are known-passing              |
| `--skip-check`  | Skip `nix flake check`                     | Debugging when checks are known-passing             |
| `--skip-all`    | Skip all validation (fmt+hooks+check)      | Emergency deployment (not recommended)              |
| `--keep-going`  | Continue building despite failures         | Building with known-broken packages                 |
| `--repair`      | Repair corrupted store paths during build  | Recovering from store corruption                    |
| `--verbose`     | Enable verbose Nix output                  | Debugging build issues                              |

### GitHub Actions (Local Testing)

| Trigger         | Command                            | Preconditions   | Post-check                          |
| --------------- | ---------------------------------- | --------------- | ----------------------------------- |
| List GH actions | `nix develop -c gh-actions-list`   | Dev shell ready | Lists available GitHub Actions jobs |
| Run GH actions  | `nix develop -c gh-actions-run`    | Dev shell ready | Runs all actions locally via act    |
| Dry run actions | `nix develop -c gh-actions-run -n` | Dev shell ready | Shows what would be executed        |

### Repository Maintenance

| Trigger              | Command                                         | Preconditions                                      | Post-check                                               |
| -------------------- | ----------------------------------------------- | -------------------------------------------------- | -------------------------------------------------------- |
| Remove files safely  | `rip <path>`                                    | Ensure file is tracked or intended for deletion.   | Confirm `git status` shows deletion; revert if mistaken. |
| Mirror updates (ghq) | `nix develop -c ghq get <repo>` or `ghq update` | Shared GHQ root configured; ensure network access. | Mirror updated under `$HOME/git/<repo>`.                 |

### Troubleshooting

| Scenario                | Resolution                                                                                                                             |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Unfree package blocked  | Add the package name to `config.nixpkgs.allowedUnfreePackages` via `modules/meta/nixpkgs-allowed-unfree.nix`.                          |
| Missing app reference   | Use `config.flake.lib.nixos.hasApp "app-name"` in a module, or run `nix eval '.#flake.nixosModules.apps'` and search for your key.     |
| Managed file drift      | Run `nix develop -c write-files` then `git diff` to reconcile generated artefacts.                                                     |
| Explore config via repl | `nix develop --accept-flake-config -c nix repl --expr 'import ./.'` then inspect `config.configurations.nixos.system76.module.imports` |

## Coding Style & Verification

| Topic      | Guidance                                                                                                                                                                     |
| ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Formatting | Use two-space indentation in Nix. Let treefmt handle formatting via `nix fmt` or `nix develop -c treefmt`.                                                                   |
| Naming     | Prefer lowercase, hyphenated identifiers. Prefix experiments with `_` to avoid auto-discovery.                                                                               |
| Imports    | Surface modules through namespace exports; avoid literal path imports.                                                                                                       |
| Validation | Keep `nix flake check --accept-flake-config` passing. Compile host closures before PRs. When changing modules, sanity-check with targeted `nix eval` or `nix run` as needed. |

### Commit & PR Expectations

- Use Conventional Commits (`type(scope): summary`)
- Keep commits focused and note affected hosts/modules
- Record validation commands run during development
- Add screenshots only for user-facing changes
- Stage only files you directly modified

## Secret Management

### Adding a new secret with sops-nix

1. **Encrypt the payload**: `sops secrets/<name>.yaml` (the `.sops.yaml` config targets everything under `secrets/`)
2. **Declare in Nix**: Add entry under `sops.secrets."<namespace>/<name>"` pointing to encrypted file
3. **Consume via module API**: Reference `config.sops.secrets."<namespace>/<name>".path` from services

Example:

```nix
sops.secrets."context7/api-key" = {
  sopsFile = ./../../secrets/context7.yaml;
  key = "context7_api_key";
  path = "%r/context7/api-key";
  mode = "0400";
};
```

## Safety & Escalation

**⚠️ FIRST: Review "CRITICAL SAFETY RULES" at the top of this document. Those rules override everything below.**

### Guardrails

| Risky Action                                        | Status                     | Alternative                                                                               |
| --------------------------------------------------- | -------------------------- | ----------------------------------------------------------------------------------------- |
| `git stash drop` or `git stash clear`               | **ABSOLUTELY FORBIDDEN**   | **NEVER delete stashes.** Leave them or use `git stash apply` to keep them.               |
| `git reset --hard`, `git clean -fd`                 | **ABSOLUTELY FORBIDDEN**   | **Ask user first.** All destructive git operations require explicit approval.             |
| `rm` or `rm -rf` on user files                      | **ABSOLUTELY FORBIDDEN**   | **Use `rip` command instead.** Files can be recovered from graveyard.                     |
| `nixos-rebuild`, direct builds against live hosts   | FORBIDDEN                  | Use `nix build .#nixosConfigurations.<host>...` or `./build.sh` per playbooks.            |
| `generation-manager switch`                         | FORBIDDEN                  | Consult maintainer for approved deployment path.                                          |
| `nix-collect-garbage` or `sudo nix-collect-garbage` | FORBIDDEN                  | Request maintainer decision; prefer `nix-store --delete` on specific paths if instructed. |
| Destructive git ops (`git checkout <commit>`)       | FORBIDDEN WITHOUT APPROVAL | Use `git switch` for branches; coordinate before history edits.                           |

### When to Escalate

1. A playbook does not cover your task
2. A command fails and the remediation is unclear
3. You suspect a generated file must change (edit files module source instead)
4. Safety guardrails conflict with required work

Pause, summarize the situation, and ask vx for direction before proceeding.

## Local Mirrors

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

## MCP Tools

### Available MCP Servers

The following MCP (Model Context Protocol) tools may be available when configured. Use `/mcp` to check current configuration status.

| Tool                  | Primary Use                                             | Access Notes                                        | Example Invocation                               |
| --------------------- | ------------------------------------------------------- | --------------------------------------------------- | ------------------------------------------------ |
| `context7`            | Look up library IDs and documentation for coding tasks. | Requires network; resolves ID before fetching docs. | `context7 resolve-library-id --name <library>`   |
| `cfdocs`              | Search Cloudflare documentation.                        | Use for Workers, R2, and other CF services.         | `cfdocs search --query "Workers KV"`             |
| `cfbrowser`           | Render and capture live webpages.                       | Useful for verifying UI changes.                    | `cfbrowser get-url-html --url <page>`            |
| `deepwiki`            | Browse repository knowledge bases.                      | Supply `owner/repo` to fetch docs.                  | `deepwiki read_wiki_structure --repo owner/repo` |
| `sequential-thinking` | Record structured reasoning steps.                      | Use for complex tasks; keeps plan visible.          | `sequentialthinking start`                       |

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

## Important Reminders

### 🚨 PRIORITY #1: Data Safety

- **NEVER** delete or make user changes irrecoverable - see "CRITICAL SAFETY RULES" at top of document
- **NEVER** use `git stash drop`, `git stash clear`, `git reset --hard`, or `rm -rf` on user files
- **ALWAYS** use `rip` instead of `rm` for file deletions (recoverable from graveyard)
- **NEVER** perform destructive operations without explicit user approval

### General Practices

- **DO** what has been asked; nothing more, nothing less
- **NEVER** create files unless absolutely necessary for achieving your goal
- **ALWAYS** prefer editing existing files over creating new ones
- **NEVER** proactively create documentation files (\*.md) or README files unless explicitly requested
- Generated artefacts (.actrc, .gitignore, .sops.yaml, README.md) are managed by the files module - update upstream definitions instead
- The build.sh helper refuses to run if git worktree is dirty - use `--allow-dirty` or `ALLOW_DIRTY=1` only when necessary
