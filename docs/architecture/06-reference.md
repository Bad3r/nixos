# Reference

Quick reference for validation, troubleshooting, tooling, and terminology.

## Validation

Run the following before every push:

```bash
nix fmt
nix develop -c bash scripts/hooks/sync-pre-commit-hooks.sh
nix develop -c pre-commit run --all-files --hook-stage manual
nix run .#generation-manager -- score   # target: 35/35
nix flake check --accept-flake-config --no-build --offline
```

### Individual Commands

| Command                                                         | Purpose                                                            |
| --------------------------------------------------------------- | ------------------------------------------------------------------ |
| `nix fmt`                                                       | Format all Nix files                                               |
| `nix develop -c bash scripts/hooks/sync-pre-commit-hooks.sh`    | Sync shared git hooks and absolute config for all linked worktrees |
| `nix develop -c pre-commit run --all-files --hook-stage manual` | Run git hooks (treefmt, deadnix, statix, typos, gitleaks)          |
| `nix run .#generation-manager -- score`                         | Evaluate Dendritic pattern compliance                              |
| `nix flake check --accept-flake-config`                         | Full flake validation (with builds/checks)                         |
| `nix flake check --accept-flake-config --no-build --offline`    | Fast offline evaluation-only check                                 |

### Build Commands

| Command                                                                 | Purpose                          |
| ----------------------------------------------------------------------- | -------------------------------- |
| `nix build .#nixosConfigurations.system76.config.system.build.toplevel` | Build System76 host closure      |
| `./build.sh`                                                            | Full validation + deployment     |
| `./build.sh --skip-all`                                                 | Skip validation (emergency only) |

## Troubleshooting

| Scenario                         | Resolution                                                                                                                   |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Git hooks fail in a new worktree | Run `nix develop` (auto-sync runs in shellHook) or run `nix develop -c bash scripts/hooks/sync-pre-commit-hooks.sh` manually |
| Missing app reference            | Use `config.flake.lib.nixos.hasApp "name"` or `nix eval --json .#nixosModules.apps --apply builtins.attrNames`               |
| Helper assertion failures        | Run `nix flake check --accept-flake-config` and inspect `checks.<system>.helpers-exist`                                      |
| Managed file drift               | Run `nix develop -c write-files` then `git diff`                                                                             |
| Unfree package blocked           | Add to `config.nixpkgs.allowedUnfreePackages` in `modules/meta/nixpkgs-allowed-unfree.nix`                                   |
| "Cannot coerce null to string"   | See [Two-Context Problem](02-module-authoring.md#the-two-context-problem)                                                    |

## Introspection

```bash
# Show high-level flake outputs
nix flake show --accept-flake-config --all-systems

# Inspect aggregator keys
nix eval --accept-flake-config --json .#nixosModules --apply builtins.attrNames
nix eval --accept-flake-config --json .#homeManagerModules --apply builtins.attrNames
nix eval --accept-flake-config --json .#homeManagerModules.apps --apply builtins.attrNames

# Evaluate specific host options
nix eval .#nixosConfigurations.system76.config.boot.loader
nix eval .#nixosConfigurations.system76.config.system.build.toplevel
```

## External Tooling

| Tool                       | Purpose                  | Example                                               |
| -------------------------- | ------------------------ | ----------------------------------------------------- |
| Context7 MCP               | Documentation lookups    | Configured via `modules/integrations/mcp-servers.nix` |
| DeepWiki MCP               | GitHub repo exploration  | Query via MCP `deepwiki_fetch` with `owner/repo`      |
| `nix-index` / `nix-locate` | Find packaged binaries   | `nix-locate 'bin/act'`                                |
| `write-files`              | Regenerate managed files | `nix develop -c write-files`                          |
| `gh-actions-run`           | Local GitHub Actions     | `nix develop -c gh-actions-run -n`                    |

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
| NixOS manual mirror | `nixos-manual/`                          |
| Home Manager manual | `/home/vx/git/home-manager/docs/manual/` |
| Stylix source       | `/home/vx/git/stylix`                    |
| nixpkgs             | `/home/vx/git/nixpkgs`                   |
| sops-nix            | `/home/vx/git/sops-nix`                  |
| import-tree         | `/home/vx/git/import-tree`               |

## Next Steps

- [Pattern Overview](01-pattern-overview.md) -- Dendritic fundamentals
- [Module Authoring](02-module-authoring.md) -- writing modules correctly
- [CLAUDE.md](/home/vx/nixos/CLAUDE.md) -- full repository guide
