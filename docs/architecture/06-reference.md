# Reference

Quick reference for validation, troubleshooting, tooling, and terminology.

## Validation

Run the following before every push:

```bash
nix fmt
nix develop -c bash scripts/hooks/sync-pre-commit-hooks.sh
nix develop -c pre-commit run --all-files --hook-stage manual
nix run .#generation-manager -- score   # target: 20/20
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

| Command                                                                                  | Purpose                                               |
| ---------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| `nix build .#nixosConfigurations.<host>.config.system.build.toplevel`                    | Build any host closure (substitute `<host>`)          |
| `nix eval --accept-flake-config --json .#nixosConfigurations --apply builtins.attrNames` | List the host names available in the current checkout |
| `./build.sh`                                                                             | Full validation + deployment                          |
| `./build.sh --host <name>`                                                               | Target a specific host                                |
| `./build.sh --skip-all`                                                                  | Skip validation (emergency only)                      |

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

# Evaluate specific host options (substitute the host name)
nix eval .#nixosConfigurations.<host>.config.boot.loader
nix eval .#nixosConfigurations.<host>.config.system.build.toplevel
```

## External Tooling

| Tool                       | Purpose                  | Example                                     |
| -------------------------- | ------------------------ | ------------------------------------------- |
| Context7 MCP               | Documentation lookups    | Configured via `flake.lib.agents.mcp`       |
| DeepWiki MCP               | GitHub repo exploration  | Pass `owner/repo` to the DeepWiki MCP tools |
| `nix-index` / `nix-locate` | Find packaged binaries   | `nix-locate 'bin/act'`                      |
| `write-files`              | Regenerate managed files | `nix develop -c write-files`                |
| `gh-actions-run`           | Local GitHub Actions     | `nix develop -c gh-actions-run -n`          |

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

| Term                    | Definition                                                                                                                                                                                                             |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Aggregator**          | Attribute subtree (e.g., `flake.nixosModules.apps`) that collects modules merged via flake-parts                                                                                                                       |
| **Custom module args**  | Per-host arguments injected via `_module.args` (`metaOwner`, `secretsRoot`, `inputs`, `hostName`; `nixosAppHelpers` at flake-parts scope only); see [Module Authoring](02-module-authoring.md#custom-module-arguments) |
| **Deferred module**     | Value of type `lib.types.deferredModule`, allowing later import into submodule fixpoints                                                                                                                               |
| **Dendritic Pattern**   | Repository pattern coupling import-tree auto-discovery with aggregator-based composition                                                                                                                               |
| **import-tree**         | Function that recursively imports all `.nix` files under a directory                                                                                                                                                   |
| **perSystem**           | flake-parts construct yielding system-specific attrsets (packages, dev shells, checks)                                                                                                                                 |
| **Two-Context Problem** | Issue where `config.flake.*` and `config.home.*` exist in different evaluation contexts                                                                                                                                |

## Resource Links

The complete shared mirror inventory is documented in
[`../reference/local-mirrors.md`](../reference/local-mirrors.md). The table
below mirrors the configured common-host paths from
`modules/hosts/common/mirrors.nix` plus generated documentation paths.

| Resource                   | Location                                              |
| -------------------------- | ----------------------------------------------------- |
| Nix source                 | `/data/git/NixOS-nix`                                 |
| nixos-hardware             | `/data/git/NixOS-nixos-hardware`                      |
| nixpkgs                    | `/data/git/NixOS-nixpkgs`                             |
| Nix RFCs                   | `/data/git/NixOS-rfcs`                                |
| Lix source                 | `/data/git/git.lix.systems-lix-project-lix`           |
| Lix installer              | `/data/git/git.lix.systems-lix-project-lix-installer` |
| Lix NixOS module           | `/data/git/git.lix.systems-lix-project-nixos-module`  |
| Determinate Nix installer  | `/data/git/DeterminateSystems-nix-installer`          |
| Home Manager source        | `/data/git/nix-community-home-manager`                |
| Home Manager manual        | `/data/git/nix-community-home-manager/docs/manual/`   |
| nh                         | `/data/git/nix-community-nh`                          |
| nixd                       | `/data/git/nix-community-nixd`                        |
| nixvim                     | `/data/git/nix-community-nixvim`                      |
| noogle                     | `/data/git/nix-community-noogle`                      |
| Stylix source              | `/data/git/nix-community-stylix`                      |
| llm-agents.nix             | `/data/git/numtide-llm-agents.nix`                    |
| sops-nix                   | `/data/git/Mic92-sops-nix`                            |
| devenv                     | `/data/git/cachix-devenv`                             |
| git-hooks.nix              | `/data/git/cachix-git-hooks.nix`                      |
| Cachix docs                | `/data/git/cachix-docs.cachix.org`                    |
| lefthook                   | `/data/git/evilmartians-lefthook`                     |
| flake-parts                | `/data/git/hercules-ci-flake-parts`                   |
| flake.parts website        | `/data/git/hercules-ci-flake.parts-website`           |
| files module               | `/data/git/mightyiam-files`                           |
| treefmt                    | `/data/git/numtide-treefmt`                           |
| treefmt-nix                | `/data/git/numtide-treefmt-nix`                       |
| import-tree                | `/data/git/vic-import-tree`                           |
| Duplicati docs             | `/data/git/duplicati-documentation`                   |
| GitHub docs                | `/data/git/github-docs`                               |
| i3 Docs                    | `/data/git/i3-i3.github.io`                           |
| Firefox source/docs        | `/data/git/mozilla-firefox-firefox`                   |
| Firefox built docs         | `/data/git/mozilla-firefox-firefox-docs/current`      |
| MDN Web Docs               | `/data/git/mdn-content`                               |
| Firefox policies           | `/data/git/mozilla-policy-templates`                  |
| Enterprise admin reference | `/data/git/mozilla-enterprise-admin-reference`        |
| CPython source/docs        | `/data/git/python-cpython`                            |
| Python stable docs source  | `/data/git/python-cpython-docs/current`               |
| LibreWolf settings         | `/data/git/codeberg-librewolf-settings`               |
| better-auth                | `/data/git/better-auth-better-auth`                   |
| Cloudflare Workers SDK     | `/data/git/cloudflare-workers-sdk`                    |
| Duplicati source           | `/data/git/duplicati-duplicati`                       |
| Logseq source              | `/data/git/logseq-logseq`                             |
| mpv source                 | `/data/git/mpv-player-mpv`                            |
| openai/codex               | `/data/git/openai-codex`                              |
| rclone source              | `/data/git/rclone-rclone`                             |
| restic source              | `/data/git/restic-restic`                             |
| wappalyzer-next            | `/data/git/s0md3v-wappalyzer-next`                    |
| tridactyl                  | `/data/git/tridactyl-tridactyl`                       |
| ZAP source                 | `/data/git/zaproxy-zaproxy`                           |
| ZAP extensions             | `/data/git/zaproxy-zap-extensions`                    |
| ZAP Python API             | `/data/git/zaproxy-zap-api-python`                    |
| ZAP community scripts      | `/data/git/zaproxy-community-scripts`                 |
| fuzzdb                     | `/data/git/fuzzdb-project-fuzzdb`                     |
| mcp-zap-server             | `/data/git/dtkmn-mcp-zap-server`                      |
| NixOS manual mirror        | `docs/nixos-manual/`                                  |

## Next Steps

- [Pattern Overview](01-pattern-overview.md) -- Dendritic fundamentals
- [Module Authoring](02-module-authoring.md) -- writing modules correctly
