# AGENTS.md

This file provides guidance to coding agents working in this repository.

> IMPORTANT: Never consider backward compatibility. Eliminate legacy support by default.

## Critical Safety Rules (Read First)

These rules override all other instructions. Violations are unacceptable.

### Never Make Changes Irrecoverable

Absolutely forbidden:

- `git stash drop` or `git stash clear`
- `git reset --hard` without explicit user approval
- `git clean -fd` or similar destructive operations
- `rm -rf` on user files or directories
- Any command that permanently deletes user work

Required practices:

- Use `rip <path>` instead of `rm` for deletions (recoverable from graveyard)
- Use `git stash` when needed, but never drop stashes
- Allowed stash operations are `git stash`, `git stash list`, `git stash show`, and `git stash apply`
- `git stash pop` requires explicit user approval
- Preserve user changes; if uncertain, ask first
- Before any potentially destructive operation, stop and ask

If something is accidentally deleted:

1. Immediately attempt recovery (stash hash, reflog, `rip` graveyard, etc.)
2. Inform the user exactly what happened and what was recovered
3. Never hide or minimize deletion mistakes

## File Parsing and Search

- JSON: `jq`
- YAML/XML/TOML/CSV/INI/HCL: `yq` (use `-p` for non-YAML)
- HTML: `htmlq -f file.html '.selector'`
- SQLite: `sqlite3`
- IMPORTANT: if file is large, sample with `rg`, `head`, `tail`, or `sed`, etc..

## Error handling

- Do not hide failures; fail loudly and report actionable diagnostics

## Repository Overview

This is a NixOS configuration using the Dendritic Pattern (organic configuration growth with automatic module discovery). Files can be moved and nested freely without breaking imports.

Canonical documentation lives under `docs/architecture/`.

## Nix Configuration

| Setting                        | Value                  | Purpose                                                    |
| ------------------------------ | ---------------------- | ---------------------------------------------------------- |
| `abort-on-warn`                | `false`                | Disabled due to upstream nixpkgs warning (issue `#485682`) |
| `extra-experimental-features`  | `[ "pipe-operators" ]` | Enable pipe operator syntax in Nix expressions             |
| `allow-import-from-derivation` | `false`                | Prevent IFD for purity and reproducibility                 |
| `experimental-features`        | `nix-command flakes`   | Enable flakes and new Nix CLI                              |

These settings are mirrored in `build.sh` via `NIX_CONFIGURATION`.

## Quick-Start Checklist

| Status | Step                                                                              |
| ------ | --------------------------------------------------------------------------------- |
| OK     | Sync working tree (`git status -sb`) and review outstanding changes before edits. |
| OK     | Enter dev shell when running commands (`nix develop`).                            |
| OK     | Use execution playbooks below; confirm prerequisites and post-checks.             |
| OK     | Record validation commands in commit messages and PR descriptions.                |
| WARN   | Never run forbidden commands or modify generated artifacts directly.              |
| WARN   | If workflow is missing or ambiguous, escalate to maintainer.                      |

## Architecture and Module System

### Automatic Module Discovery

All Nix files are automatically imported as flake-parts modules. Files prefixed with `_` are ignored. Avoid literal path imports. Modules register under:

- `flake.nixosModules`
- `flake.homeManagerModules`

### Module Composition Pattern

Hosts compose modules from aggregator namespaces, not literal paths. Use `lib.hasAttrByPath` with `lib.getAttrFromPath` for optional modules to avoid ordering issues.

### Flake Input Deduplication

Inputs prefixed with `dedupe_` exist for dependency deduplication through `.follows`. If no `follows` references remain, remove the `dedupe_` input.

### Repository Layout

| Domain              | Location                                          | Notes                                                                                              |
| ------------------- | ------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| NixOS modules       | `modules/`                                        | Auto-loaded. Host-specific logic under `modules/system76`; shared bundles grouped by domain.       |
| Shared derivations  | `packages/`                                       | Common build logic shared between modules.                                                         |
| Helper scripts      | `scripts/`                                        | Operational tooling.                                                                               |
| Documentation       | `docs/`, `nixos-manual/`                          | Long-form references and local workflows.                                                          |
| Secrets             | `secrets/`                                        | Encrypted payloads managed via `sops.secrets`.                                                     |
| Generated artifacts | `.actrc`, `.gitignore`, `.sops.yaml`, `README.md` | Owned by the files module. Update source definitions instead of editing generated output directly. |

### Module Authoring Guidelines (`modules/apps/*`)

Use the standard options namespace and explicit opt-in:

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.<package-name>.extended;
  packageModule = {
    options.programs.<package-name>.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
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
  flake.nixosModules.apps.<package-name> = packageModule;
}
```

## Execution Playbooks

### Branch Workflow

Rule: Use a dedicated worktree and PR for changes. Do not commit directly to `main` unless explicitly approved.

| Step   | Command                                                             |
| ------ | ------------------------------------------------------------------- |
| Create | `git worktree add $HOME/trees/nixos/<type>-<name> -b <type>/<name>` |
| Work   | `cd $HOME/trees/nixos/<type>-<name>` then commit changes            |
| PR     | `gh pr create --title "<type>(scope): summary" --body "..."`        |

Branch type should follow Conventional Commits prefixes.

PR body should include:

- `## Summary`
- `## Test plan`

### Development Environment

| Trigger            | Command                                                         | Preconditions                                   | Post-check                                                         |
| ------------------ | --------------------------------------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------ |
| Start work         | `nix develop`                                                   | Clean tree; network available for substituters. | Dev tools available (`treefmt`, `pre-commit`, etc.).               |
| Format sources     | `nix fmt`                                                       | Run at repo root.                               | No remaining formatting diffs in `git status`.                     |
| Run hooks          | `nix develop -c pre-commit run --all-files --hook-stage manual` | Dev shell ready; workspace writable.            | Exit code 0; review reported TODOs/failures.                       |
| Generate artifacts | `nix develop -c write-files`                                    | Dev shell ready; managed files may update.      | Review diffs in `.actrc`, `.gitignore`, `.sops.yaml`, `README.md`. |

### Validation and Builds

| Trigger             | Command                                                               | Preconditions                                                   | Post-check                                     |
| ------------------- | --------------------------------------------------------------------- | --------------------------------------------------------------- | ---------------------------------------------- |
| Verify flake health | `nix flake check --accept-flake-config --no-build --offline`          | Dev shell recommended.                                          | Exit code 0; resolve reported failures.        |
| Build host          | `nix build .#nixosConfigurations.<host>.config.system.build.toplevel` | Replace `<host>`. Do not use `--allow-dirty` unless instructed. | Build completes; capture resulting store path. |
| Validate/deploy     | `./build.sh [OPTIONS]`                                                | Clean tree unless `--allow-dirty` is explicitly required.       | Script exits 0; capture logs on failure.       |
| Update inputs       | `./build.sh --update`                                                 | Clean tree recommended.                                         | Review `flake.lock` changes.                   |

#### `build.sh` options

| Flag            | Purpose                                   | Use When                                         |
| --------------- | ----------------------------------------- | ------------------------------------------------ |
| `--host <name>` | Target specific hostname                  | Deploying to non-current host                    |
| `--boot`        | Install for next boot                     | Testing before activation                        |
| `--offline`     | Build without network access              | Working offline/testing substituter independence |
| `--allow-dirty` | Override clean tree requirement           | Emergency fix only                               |
| `--update`      | Run `nix flake update` before build       | Updating all inputs                              |
| `--skip-fmt`    | Skip formatting step                      | Debugging known-good formatting                  |
| `--skip-hooks`  | Skip pre-commit hooks                     | Debugging known-good hooks                       |
| `--skip-check`  | Skip `nix flake check`                    | Debugging known-good checks                      |
| `--skip-all`    | Skip all validation                       | Emergency deployment only                        |
| `--keep-going`  | Continue despite failures                 | Building with known-broken packages              |
| `--repair`      | Repair corrupted store paths during build | Recovering from store corruption                 |
| `--verbose`     | Enable verbose Nix output                 | Debugging build issues                           |

### GitHub Actions (Local)

| Trigger   | Command                            | Preconditions   | Post-check                     |
| --------- | ---------------------------------- | --------------- | ------------------------------ |
| List jobs | `nix develop -c gh-actions-list`   | Dev shell ready | Lists available workflow jobs  |
| Run jobs  | `nix develop -c gh-actions-run`    | Dev shell ready | Runs actions locally via `act` |
| Dry run   | `nix develop -c gh-actions-run -n` | Dev shell ready | Shows planned execution        |

### Troubleshooting

| Scenario               | Resolution                                                                                              |
| ---------------------- | ------------------------------------------------------------------------------------------------------- |
| Unfree package blocked | Add package to `config.nixpkgs.allowedUnfreePackages` in `modules/meta/nixpkgs-allowed-unfree.nix`.     |
| Missing app reference  | Ensure that the file is tracked by git.                                                                 |
| Explore config in repl | `nix develop --accept-flake-config -c nix repl --expr 'import ./.'` then inspect config module imports. |

## Coding Style and Verification

| Topic      | Guidance                                                                                                                                              |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Naming     | Prefer lowercase, hyphenated identifiers. Prefix experiments with `_` to avoid auto-discovery.                                                        |
| Imports    | Expose modules through namespace exports; avoid literal path imports.                                                                                 |
| Validation | Keep `nix flake check --accept-flake-config` passing. Build host closures before PRs. Use targeted `nix eval`/`nix run` checks when changing modules. |

### Commit and PR Expectations

- Use Conventional Commits: `type(scope): summary`
- Keep one logical concern per commit
- Record validation commands run
- Include screenshots only for user-facing changes
- Stage only files you directly modified

## Secret Management

### Adding a secret with `sops-nix`

1. Encrypt payload: `sops secrets/<name>.yaml`
2. Declare in Nix under `sops.secrets."<namespace>/<name>"`
3. Consume via `config.sops.secrets."<namespace>/<name>".path`

Example:

```nix
sops.secrets."context7/api-key" = {
  sopsFile = ./../../secrets/context7.yaml;
  key = "context7_api_key";
  path = "%r/context7/api-key";
  mode = "0400";
};
```

## Safety and Escalation

Escalate when:

1. A needed workflow is not documented
2. A command fails and remediation is unclear

Pause, summarize the issue, and ask for direction.

## Local Mirrors

| Name           | Path                                   | Use When                                                       |
| -------------- | -------------------------------------- | -------------------------------------------------------------- |
| Stylix         | `/data/git/nix-community-stylix`       | Inspect source or apply local patches.                         |
| Home Manager   | `/data/git/nix-community-home-manager` | Review module behavior or backport fixes.                      |
| i3 Docs        | `/data/git/i3-i3.github.io`            | Reference i3 documentation offline.                            |
| nixpkgs        | `/data/git/NixOS-nixpkgs`              | Inspect/patch upstream expressions.                            |
| nixos-hardware | `/data/git/NixOS-nixos-hardware`       | Pull hardware profiles and troubleshoot host hardware options. |
| nixvim         | `/data/git/nix-community-nixvim`       | Examine NixVim modules and options.                            |
| treefmt-nix    | `/data/git/numtide-treefmt-nix`        | Adjust formatter behavior or pinning.                          |
| git-hooks.nix  | `/data/git/cachix-git-hooks.nix`       | Update hook definitions or debug pre-commit failures.          |
| sops-nix       | `/data/git/Mic92-sops-nix`             | Manage encrypted secret integrations.                          |
| import-tree    | `/data/git/vic-import-tree`            | Review/extend auto-loading behavior.                           |
| files module   | `/data/git/mightyiam-files`            | Update generated artifact sources (e.g., `.gitignore`).        |

## Practices

- Do what was asked, nothing more and nothing less.
- Prefer editing existing files over creating new ones
- If an issue is upstream, do not add a local wrapper or workaround unless the user explicitly asks for it or approves it.
- IMPORTANT: For any task task, you **MUST** resolve it idiomatically and following best-practices.
- IMPORTANT: DO NOT BE LAZY OR TAKE SHORTCUTS
