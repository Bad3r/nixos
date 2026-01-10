# Trees Nix Configuration Architecture

This document provides a single source of truth for how the repository’s NixOS and Home Manager configuration fits together. It consolidates material from existing guides (`dendritic-pattern-reference.md`, `module-structure-guide.md`, `home-manager-aggregator.md`, and others) and adds actionable references, commands, and resource links for deeper exploration.

> **Audience.** Engineers who need to extend modules, adjust the System76 host, wire secrets, or run validation tooling across this repository.

---

## 1. Flake Composition & Auto-Import

| Component       | Location / Reference           | Purpose                                                                                                          |
| --------------- | ------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| `flake.nix`     | `flake.nix:1-200`              | Pins inputs (nixpkgs, nixvim, stylix, etc.), sets `nixConfig`, and wraps outputs with `flake-parts.lib.mkFlake`. |
| import-tree     | `inputs.import-tree ./modules` | Recursively imports every `.nix` file under `modules/` unless it starts with `_`.                                |
| Default systems | `modules/systems.nix`          | Declares supported build targets (currently `x86_64-linux`, `aarch64-darwin`).                                   |
| Flake arguments | `_module.args` in `flake.nix`  | Provides `rootPath`, `inputs`, and a default `pkgs` set to every module.                                         |

**Key idea:** every module contributes to one (or more) aggregator namespaces (see Section 2). Avoid literal `./path` imports—let import-tree and aggregators wire things for you.

### Quick verification commands

```bash
# Inspect flake inputs and their locked revisions
nix flake metadata

# Explore configuration via repl with the same auto-import context
nix develop --accept-flake-config -c nix repl --expr 'import ./.'
```

---

## 2. Aggregator Map (System Layer)

All modules feed into `flake.nixosModules` and supporting helpers so that hosts compose features by name rather than by path.

### 2.1 App registry

- **Helper:** `modules/meta/nixos-app-helpers.nix` flattens all `flake.nixosModules.apps.<name>` exports and exposes `getApp`, `getApps`, `hasApp`, `getAppOr` via `config.flake.lib.nixos`.
- **Per-app module pattern:** `modules/apps/<app>.nix` (see `modules/apps/codex.nix`, `modules/apps/dnsleak.nix`) adds packages to `environment.systemPackages` and optionally registers per-system packages.
- **Style guidance:** `docs/apps-module-style-guide.md` documents the header comment and module body conventions (two-space indent, documentation block, etc.).

**Example – pull app modules into the System76 profile:**

```nix
{ config, ... }:
{
  configurations.nixos.system76.module.imports =
    config.flake.lib.nixos.getApps [
      "python"
      "uv"
      "ruff"
      "pyright"
    ];
}
```

### 2.2 System76 host modules

- Every file under `modules/system76/` contributes directly to `configurations.nixos.system76.module`.
- Feature modules are organized by concern (`packages.nix`, `security-tools.nix`, `pipewire.nix`, `home-manager-gui.nix`, and others) so the host profile reads like a manifest of explicit features instead of an opaque bundle.
- Language toolchains are enabled in `modules/system76/imports.nix` via `languages.<name>.extended.enable`, keeping the existing app registry reusable without an intermediate role layer.

### 2.3 Shared system helpers

- Hardware profiles exposed via `flake.nixosModules."system76-support"` and `flake.nixosModules."hardware-lenovo-y27q-20"` remain available for hosts to import directly.
- Virtualization helpers under `modules/virtualization/*.nix` publish `{virt,docker,libvirt,vmware,ovftool}` entries so the System76 profile can opt into specific stacks.

### 2.4 System-level utilities

- `modules/meta/ci.nix` validates that the app helper namespace (`config.flake.lib.nixos`) exposes `getApp`, `getApps`, `getAppOr`, and `hasApp`.
- `modules/files.nix` integrates the mightyiam/files writer to regenerate managed artefacts (for example `README.md`, `.sops.yaml`).

---

## 3. Home Manager Aggregator & Secrets

### 3.1 Base wiring

- `modules/home-manager/nixos.nix` imports `inputs.home-manager.nixosModules.home-manager`, defines `home-manager.extraAppImports`, and adds default shared modules for the owner user.
- Home Manager base configuration lives in `modules/home-manager/base.nix`, which uses DAG helpers (`hm.dag.entryAfter`) to ensure secrets’ runtime directories exist.

### 3.2 App catalog & GUI bundle

- Individual HM apps live under `modules/hm-apps/<name>.nix`. Each exports `flake.homeManagerModules.apps.<name>` with optional program enablement (see `hm-apps/alacritty.nix`).
- `modules/system76/home-manager-apps.nix` shows how to append host-specific GUI app lists via `home-manager.extraAppImports` and `home-manager.sharedModules`.

### 3.3 Secrets helpers

- System secrets are declared in `modules/security/secrets.nix`.
- Home-level secrets helpers (`modules/home/context7-secrets.nix`, `modules/home/r2-secrets.nix`) guard SOPS declarations behind `builtins.pathExists` checks and place decrypted material under the user’s `$HOME`.
- `.sops.yaml` policy is generated by `modules/security/sops-policy.nix` through the files writer.
- The Context7 secret feeds the MCP catalog in `lib/mcp-servers.nix`.

**HM diagnostics command (Home Manager CLI is not bundled by default):**

```bash
nix develop -c nix run nixpkgs#home-manager -- --flake .#vx switch --dry-run
```

The dev shell keeps evaluation tools lightweight; if you prefer a `home-manager` binary on the path, add it to `modules/devshell.nix` or rely on a user profile installation before running the command above.

---

## 4. Host Composition (System76 Example)

Host definitions live under `configurations.nixos.<host>.module` (typed as `lib.types.deferredModule` in `modules/configurations/nixos.nix`). The System76 stack demonstrates the pattern:

1. `modules/system76/imports.nix` collects baseline modules (System76 hardware profiles, shared security helpers, the Lenovo monitor profile, virtualization helpers) and exposes the resulting host under `configurations.nixos.system76.module`.
2. Feature-specific files (`modules/system76/security-tools.nix`, `packages.nix`, `pipewire.nix`, `home-manager-gui.nix`, `hostname.nix`, etc.) extend `configurations.nixos.system76.module` directly.
3. The `flake` attribute in `imports.nix` exports `nixosConfigurations.system76`, propagating `system.configurationRevision` when the `self` input provides one.

**Add a new host (checklist):**

1. Create `modules/<host>/imports.nix` referencing shared modules via aggregators.
2. Add host-specific files under `modules/<host>/`.
3. Register the host under `configurations.nixos.<host>.module` (either inline or via `imports.nix`).
4. Run `nix eval .#nixosConfigurations.<host>.config.system.build.toplevel` to confirm the graph builds.

---

## 5. Packages, perSystem, and Tooling

| Area                   | Modules / Paths                                           | Notes                                                                                                              |
| ---------------------- | --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| Custom derivations     | `packages/<name>/default.nix`                             | Packages such as `codex`, `raindrop`, and `wappalyzer-next` are exposed via `perSystem.packages`.                  |
| App wiring             | `modules/apps/<name>.nix`                                 | Mirrors per-system packages into system / HM environments when needed.                                             |
| Dev shells             | `modules/devshell.nix`, `modules/devshell/pentesting.nix` | Uses `inputs.make-shell` and `treefmt-nix` to define `nix develop` shells and specialized pentesting environments. |
| Git hooks / formatting | `modules/meta/git-hooks.nix`                              | Enables `nixfmt`, `deadnix`, `statix`, `typos`, managed file drift detection, etc.                                 |
| Generation manager     | `modules/meta/generation-manager.nix`                     | Provides the `generation-manager` CLI (packaged under `config.flake.packages.<system>.generation-manager`).        |

**Dev shell onboarding:**

```bash
nix develop
# Within the shell:
write-files                 # regenerate managed docs if needed
gh-actions-list             # list workflows via act
generation-manager score    # verify Dendritic pattern compliance (>= 90/90)
```

---

## 6. Validation & Continuous Checks

Recommended command sequence before raising a PR (mirrors `docs/dendritic-pattern-reference.md`):

```bash
nix fmt
nix develop -c pre-commit run --all-files
generation-manager score
nix flake check --accept-flake-config
```

Additional diagnostics:

- `nix eval .#nixosConfigurations.system76.config.boot.loader` – introspect host options.
- `nix develop -c nix repl --expr 'import ./.` followed by `:p config.configurations.nixos.system76.module.imports` – inspect the assembled host profile.
- `rg --files` or `rg "flake.nixosModules" -n modules` – explore module exports (ripgrep preferred for speed).

---

## 7. Troubleshooting & Patterns

| Scenario                  | Steps                                                                                                                                  |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Missing app reference     | Use `config.flake.lib.nixos.hasApp "app-name"` inside a module, or run `nix eval '.#flake.nixosModules.apps'` and search for your key. |
| Helper assertion failures | See `flake.checks.helpers-exist` from `modules/meta/ci.nix`; run `nix flake check` to surface errors with context.                     |
| Managed file drift        | Run `write-files` (from dev shell) then `git diff` to reconcile generated artefacts.                                                   |
| Unfree package blocked    | Add the package name to `config.nixpkgs.allowedUnfreePackages` via `modules/meta/nixpkgs-allowed-unfree.nix`.                          |

---

## 8. Resource & Reference Index

| Topic                     | Local Reference                       | Description                                                                                         |
| ------------------------- | ------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Dendritic overview        | `docs/dendritic-pattern-reference.md` | Strategy for auto-imports and aggregator usage.                                                     |
| Module authoring          | `docs/module-structure-guide.md`      | Patterns for module shape, namespaces, and migration tips.                                          |
| Home Manager details      | `docs/home-manager-aggregator.md`     | Expanded coverage of HM namespace layout.                                                           |
| App metadata style        | `docs/apps-module-style-guide.md`     | Header / doc block requirements for `modules/apps`.                                                 |
| SOPS practices            | `docs/sops/` directory                | Secrets workflow (see generated `.sops.yaml`).                                                      |
| Local NixOS manual mirror | `nixos_docs_md/`                      | Markdown mirror of the upstream NixOS manual (search with `rg` or open `options.html`).             |
| Home Manager manual       | `docs/manual/writing-modules.md`      | Pointers to the local `/home/vx/git/home-manager/docs/manual/` mirror, including `writing-modules`. |

**Handy commands for exploration:**

```bash
# Search the local NixOS documentation mirror
rg --no-heading --line-number "module system" nixos_docs_md

# Open Home Manager manual section in $PAGER
sed -n '1,160p' /home/vx/git/home-manager/docs/manual/writing-modules.md

# Fetch flake-parts docs via the Context7 MCP server (independent of the dev shell)
npx -y @upstash/context7-mcp \
  --api-key "$(cat ~/.local/share/context7/api-key)" \
  resolve-library-id --name flake-parts

# Run managed-file + workflow helpers shipped in the dev shell
nix develop -c write-files
nix develop -c gh-actions-run -n
```

---

## 9. Task Playbooks & Examples

### 9.1 Add a new system app

1. Scaffold `modules/apps/<name>.nix` using the style guide.
2. Register optional per-system packages through `perSystem`.
3. Enable the app in `modules/system76/apps-enable.nix` if the System76 profile should include it by default.
4. Run `nix fmt` and `pre-commit run --all-files`.

### 9.3 Define a new host

1. Add host module under `modules/<host>/`.
2. Register the host via `configurations.nixos.<host>.module`.
3. Evaluate `nix eval .#nixosConfigurations.<host>.config.system.build.toplevel` for a dry build.

---

## 10. External Tooling & Integrations

| Tool                                 | Purpose                                                                                        | Example                                                                                 |
| ------------------------------------ | ---------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| Context7 MCP (`lib/mcp-servers.nix`) | Model Context Protocol server for docs lookups once `context7-secrets.nix` renders the API key | `npx -y @upstash/context7-mcp --api-key "$(cat ~/.local/share/context7/api-key)" serve` |
| DeepWiki (`deepwiki`)                | Explore GitHub repositories linked to modules                                                  | `deepwiki read-wiki-structure --repo nix-community/home-manager`                        |
| `nix-index` / `nix-locate`           | Identify packaged binaries before writing modules                                              | `nix develop -c nix-locate 'bin/act'`                                                   |
| `write-files` (dev shell)            | Regenerate managed artefacts tracked by the files module                                       | `nix develop -c write-files && git diff --stat`                                         |
| `gh-actions-run` (dev shell)         | Dry-run GitHub Actions locally with `act` defaults                                             | `nix develop -c gh-actions-run -n`                                                      |

Ensure `modules/home/context7-secrets.nix` and associated SOPS entries are populated when invoking Context7. The MCP server is defined in `lib/mcp-servers.nix` and is consumed by CLI tools (for example Claude Code) without depending on the repository dev shell; run it directly with `npx` or reuse the wrapper that module produces. The `write-files` and `gh-actions-run` helpers ship automatically with the dev shell definition in `modules/devshell.nix`.

---

## 11. Glossary

- **Aggregator** – Attribute subtree (e.g. `flake.nixosModules.apps`) that collects modules merged via flake-parts.
- **Deferred module** – Value of type `lib.types.deferredModule`, allowing later import into submodule fixpoints (see `modules/configurations/nixos.nix`).
- **Per-system** – `flake-parts` construct that yields system-specific attrsets (packages, dev shells, checks).
- **Dendritic pattern** – Repository pattern that couples import-tree auto-discovery with aggregator-based composition.

---

This guide should evolve with the repository. When adding major features (new host families, secrets workflows, or dev tooling), update this file and link supporting detail from specialized documents under `docs/`.
