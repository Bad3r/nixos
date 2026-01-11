# Reference

Quick reference for validation, troubleshooting, tooling, and terminology.

## Validation

Run the following before every push:

```bash
nix fmt
nix develop -c pre-commit run --all-files
generation-manager score    # Target: 90/90
nix flake check --accept-flake-config
```

### Individual Commands

| Command                                     | Purpose                                        |
| ------------------------------------------- | ---------------------------------------------- |
| `nix fmt`                                   | Format all Nix files                           |
| `nix develop -c pre-commit run --all-files` | Run git hooks (nixfmt, deadnix, statix, typos) |
| `generation-manager score`                  | Evaluate Dendritic pattern compliance          |
| `nix flake check --accept-flake-config`     | Full flake validation                          |
| `nix flake check --no-build --offline`      | Quick check without building                   |

### Build Commands

| Command                                                               | Purpose                          |
| --------------------------------------------------------------------- | -------------------------------- |
| `nix build .#nixosConfigurations.<host>.config.system.build.toplevel` | Build host closure               |
| `./build.sh`                                                          | Full validation + deployment     |
| `./build.sh --skip-all`                                               | Skip validation (emergency only) |

## Troubleshooting

| Scenario                       | Resolution                                                                                 |
| ------------------------------ | ------------------------------------------------------------------------------------------ |
| Missing app reference          | Use `config.flake.lib.nixos.hasApp "name"` or `nix eval '.#flake.nixosModules.apps'`       |
| Helper assertion failures      | Run `nix flake check` — see `flake.checks.helpers-exist`                                   |
| Managed file drift             | Run `nix develop -c write-files` then `git diff`                                           |
| Unfree package blocked         | Add to `config.nixpkgs.allowedUnfreePackages` in `modules/meta/nixpkgs-allowed-unfree.nix` |
| "Cannot coerce null to string" | See [Two-Context Problem](02-module-authoring.md#the-two-context-problem)                  |

## Introspection

```bash
# Explore via REPL
nix develop --accept-flake-config -c nix repl --expr 'import ./.'

# Inside REPL
:p config.flake.nixosModules
:p config.configurations.nixos.system76.module.imports

# Evaluate specific options
nix eval .#nixosConfigurations.system76.config.boot.loader
nix eval .#nixosConfigurations.system76.config.system.build.toplevel
```

## External Tooling

| Tool                       | Purpose                  | Example                                          |
| -------------------------- | ------------------------ | ------------------------------------------------ |
| Context7 MCP               | Documentation lookups    | Via `lib/mcp-servers.nix`                        |
| DeepWiki                   | GitHub repo exploration  | `deepwiki read-wiki-structure --repo owner/repo` |
| `nix-index` / `nix-locate` | Find packaged binaries   | `nix-locate 'bin/act'`                           |
| `write-files`              | Regenerate managed files | `nix develop -c write-files`                     |
| `gh-actions-run`           | Local GitHub Actions     | `nix develop -c gh-actions-run -n`               |

## Dev Shell Helpers

Available after `nix develop`:

| Command                    | Purpose                                |
| -------------------------- | -------------------------------------- |
| `write-files`              | Regenerate README.md, .sops.yaml, etc. |
| `gh-actions-list`          | List available GitHub Actions jobs     |
| `gh-actions-run`           | Run GitHub Actions locally via act     |
| `gh-actions-run -n`        | Dry-run GitHub Actions                 |
| `generation-manager score` | Check Dendritic pattern compliance     |

## Glossary

| Term                    | Definition                                                                                       |
| ----------------------- | ------------------------------------------------------------------------------------------------ |
| **Aggregator**          | Attribute subtree (e.g., `flake.nixosModules.apps`) that collects modules merged via flake-parts |
| **Deferred module**     | Value of type `lib.types.deferredModule`, allowing later import into submodule fixpoints         |
| **Dendritic Pattern**   | Repository pattern coupling import-tree auto-discovery with aggregator-based composition         |
| **import-tree**         | Function that recursively imports all `.nix` files under a directory                             |
| **perSystem**           | flake-parts construct yielding system-specific attrsets (packages, dev shells, checks)           |
| **Two-Context Problem** | Issue where `config.flake.*` and `config.home.*` exist in different evaluation contexts          |

## Resource Links

| Resource            | Location                                 |
| ------------------- | ---------------------------------------- |
| NixOS manual mirror | `nixos_docs_md/`                         |
| Home Manager manual | `/home/vx/git/home-manager/docs/manual/` |
| Stylix source       | `/home/vx/git/stylix`                    |
| nixpkgs             | `/home/vx/git/nixpkgs`                   |
| sops-nix            | `/home/vx/git/sops-nix`                  |
| import-tree         | `/home/vx/git/import-tree`               |

## Next Steps

- [Pattern Overview](01-pattern-overview.md) — Dendritic fundamentals
- [Module Authoring](02-module-authoring.md) — writing modules correctly
- [CLAUDE.md](/home/vx/nixos/CLAUDE.md) — full repository guide
