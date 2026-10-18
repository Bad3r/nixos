# nixos: Onboarding Guide

**nixos** is a multi-host NixOS and Home Manager configuration built on the **Dendritic Pattern**: every Nix file is a flake-parts module that `import-tree` imports automatically.
Files prefixed with `_` are omitted, and nothing imports a module by literal path.
It composes per-host system and Home Manager configurations with sops-nix secrets, Stylix theming, and a `build.sh` validate-and-deploy pipeline.

- [Architecture](architecture/README.md): the Dendritic Pattern reference, in reading order.
- [Layers and File Map](onboarding-layers.md): the directories and their load-bearing files.

## Project Overview

- **Languages**: Nix first, then Python and Shell, plus JSON, YAML, TOML, SQL, and Markdown data.
- **Frameworks**: flake-parts, import-tree, home-manager, sops-nix, stylix, treefmt-nix, git-hooks.nix, nixos-hardware, and GitHub Actions.
- **Hosts**: `songbird` and `tpnix`.

## Key Concepts

These patterns recur everywhere:

- [Automatic module discovery](architecture/01-pattern-overview.md#automatic-module-discovery): a new module is a new file in the right place, never an import-list entry.
- [Aggregator namespaces](architecture/01-pattern-overview.md#aggregator-namespaces): modules register under shared namespaces, and hosts compose them by name.
- [The Two-Context Problem](architecture/02-module-authoring.md#the-two-context-problem): which `config` a given attrset sees, the most important pitfall.
- [App registry](guides/apps-module-registry.md): the rows that decide which programs each host installs.
- [Home Manager integration](guides/apps-module-home-manager.md): NixOS app modules install programs, and Home Manager modules configure them.
- [Host Composition](architecture/05-host-composition.md): the shared `hosts-common` aggregate loads before each host's own module, so host settings win.
- [Custom package overlays](guides/custom-packages-overlays.md): an overlay joins `nixpkgs.overlays` only where its app's row is on.
- [Custom packages](guides/custom-packages-style-guide.md): a derivation pinned by `hashes.json` and refreshed by its `update.py`.
- [Secrets](sops/README.md): sops-nix payloads in the `secrets/` submodule, decrypted by one age key.
- `modules/agents/system-prompt.nix` renders the shared agent baseline into the user-level `~/.claude/CLAUDE.md` and `~/.config/codex/AGENTS.md`, and `modules/agents/mcp.nix` compiles the per-client MCP server lists.
  Edit the source, not the rendered output.
- `build.sh` runs the git hooks and `nix flake check`, then switches or boots through `nh os`, and refuses a dirty tree without `--allow-dirty`.
  `.github/workflows/check.yml` enforces the same Dendritic compliance in CI.

## Guided Tour

The reading path runs from what the project is to how it ships, each step building on the last:

01. What this project is: `README.md`, with its four pillars of auto-discovery, the `build.sh` pipeline, the dual package pattern, and secrets.
02. The Dendritic Pattern: [Architecture](architecture/README.md) and [Pattern Overview](architecture/01-pattern-overview.md).
03. The flake entry point: `flake.nix`, with `nixConfig`, inputs pinned to Bad3r forks, and `mkFlake { imports = [ ... (import-tree ./modules) ]; }`.
04. How a file becomes a module: [Module Authoring](architecture/02-module-authoring.md), for placement rules, the `pkgs` split, and the Two-Context Problem.
05. NixOS modules and the app registry: [NixOS Modules](architecture/03-nixos-modules.md), `modules/hosts/common/apps-base.nix`, and `modules/hosts/common/apps-enable.nix`.
06. Assembling a host: [Host Composition](architecture/05-host-composition.md), `modules/configurations/nixos.nix`, and `modules/hosts/common/registry.nix`.
07. Per-host composition and rows: `modules/hosts/common/imports.nix`, `modules/songbird/apps-enable.nix`, and `modules/tpnix/apps-enable.nix`.
08. Home Manager, the dual-module pattern: [Home Manager](architecture/04-home-manager.md), `modules/home-manager/nixos.nix`, and `modules/home-manager/base.nix`.
09. Secrets with sops-nix: `modules/security/sops-runtime.nix`, `modules/hosts/common/sops.nix`, and `modules/security/secrets.nix`.
10. Custom packages and overlays: `modules/hosts/common/custom-overlays-base.nix`, `packages/restringer/default.nix`, and its `hashes.json`.
11. The AI agents layer: `modules/agents/system-prompt.nix`, `modules/agents/claude-code/home.nix`, `modules/agents/codex/home.nix`, and `modules/agents/mcp.nix`.
12. Theming with Stylix: `modules/stylix/stylix.nix`, whose base16 scheme comes from the `tinted-schemes` input.
13. Validation, tooling, and deployment: `modules/devshell.nix`, `modules/meta/treefmt.nix`, `modules/meta/pre-commit.nix`, `build.sh`, and `.github/workflows/check.yml`.

## Complexity Hotspots

These files concentrate the most logic or the most cross-cutting effects, so a change to one ripples widely.

Architectural core:

- `flake.nix`: the inputs set and the `_module.args` seed; a mistake here breaks every host.
- `modules/configurations/nixos.nix`: the host builder, which controls the common-versus-host layering.
- `modules/hosts/common/apps-enable.nix`: the baseline rows every host's registry checks compare against.
- `modules/home-manager/nixos.nix`: app-key resolution and the Home Manager wiring into NixOS.

Cross-cutting service and domain modules:

- `modules/services/duplicati-r2.nix` and `modules/lib/r2-runtime.nix`: R2 backups, runtime systemd materialization, and external-flake gating.
- `modules/networking/ssh.nix` and `modules/hosts/common/usbguard.nix`: security-sensitive access policy.
- `modules/stylix/stylix.nix`: GTK, Qt, Firefox, and mpv theming across the system and Home Manager.

Agents subsystem:

- `modules/agents/mcp.nix`, `modules/agents/system-prompt.nix`, `modules/agents/skills.nix`, and the `modules/agents/codex/_*.nix` helpers: the single source for prompts and MCP, whose output is generated, so fixes go in the source.

Packaging machinery in Python:

- `packages/duplicati-r2-tools/*.py`: the shared CLI substrate, the extract and list commands, and their regression fixtures.
- `scripts/updater/*.py` and `packages/*/update.py`: the hash-pinning updaters, which handle loosely typed JSON with `typing.cast`.

CI and shell tooling:

- `.github/scripts/upstream-tracker.sh`, `.github/workflows/{check,update-flake}.yml`, `scripts/gh-cli/pr-comments-mgmt.sh`, and `scripts/url-catalog-add.py`.
