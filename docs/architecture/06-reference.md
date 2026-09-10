# Reference

Quick reference for validation, introspection, tooling, and terminology.
Symptoms and their resolutions live in
[Troubleshooting](07-troubleshooting.md).

## Validation

Run the following before every push:

```bash
nix run path:.#treefmt -- .
nix develop path:. -c bash scripts/hooks/sync-pre-commit-hooks.sh
nix develop path:. -c pre-commit run --all-files --hook-stage manual
nix run path:.#generation-manager -- score   # target: 20/20
nix flake check path:. --accept-flake-config --no-build --offline
```

The branch workflow in `AGENTS.md` puts work in a linked worktree, where Lix cannot fetch a clean checkout as a `git+file` flake, since `.git` is a file there and not a directory.
Flake commands in a linked worktree take an explicit `path:.` installable; the primary checkout takes the bare form.
Two cases `path:.` cannot fix.
`nix fmt` resolves the hardcoded `.` installable from `lix/nix/fmt.cc`, so a linked worktree reaches the formatter as `nix run path:.#treefmt -- .`, or `-- <file>` for a targeted run.
A command that writes `flake.lock` back needs an absolute ref such as `"path:$PWD"`, because the write goes through Lix's `getAbsPath`; that covers `nix flake metadata --refresh` and `nix flake update`.
A dirty worktree masks all of it, because Lix copies the working tree instead of fetching the revision, so a command that passes with uncommitted changes present can still exit 1 once the tree is clean.

### Credential Scanning

`hook-gitleaks` scans commits rather than the worktree, so its scope depends on
how it is invoked. At `pre-push` it reads only the range pre-commit reports in
`PRE_COMMIT_FROM_REF` and `PRE_COMMIT_TO_REF`, and each gitlink only across the
commits its pointer newly reaches, so a push does not re-read history it has
already published. Every reduced scope is named in the hook's own output.

The full sweep runs with neither variable set, which is how
`.github/workflows/check.yml` invokes it on the merge path and how it runs by
hand:

```bash
nix run path:.#hook-gitleaks
```

A shallow clone is refused rather than reported clean, so run this against a
complete history. Suppression goes through `.gitleaks-baseline.json`, whose
entries the hook announces whenever they filter a pass;
`.gitleaksignore` is refused outright, since it filters findings with no
review and cannot be turned off.

### Individual Commands

| Command                                                                | Purpose                                                            |
| ---------------------------------------------------------------------- | ------------------------------------------------------------------ |
| `nix run path:.#treefmt -- .`                                          | Format all Nix files                                               |
| `nix develop path:. -c bash scripts/hooks/sync-pre-commit-hooks.sh`    | Sync shared git hooks and absolute config for all linked worktrees |
| `nix develop path:. -c pre-commit run --all-files --hook-stage manual` | Run git hooks (treefmt, deadnix, statix, typos, gitleaks)          |
| `nix run path:.#hook-gitleaks`                                         | Sweep the full history for credentials, the scan CI runs           |
| `nix run path:.#generation-manager -- score`                           | Evaluate Dendritic pattern compliance                              |
| `nix flake check path:. --accept-flake-config`                         | Full flake validation (with builds/checks)                         |
| `nix flake check path:. --accept-flake-config --no-build --offline`    | Fast offline evaluation-only check                                 |

### Build Commands

| Command                                                                                         | Purpose                                               |
| ----------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| `nix build "path:.#nixosConfigurations.<host>.config.system.build.toplevel"`                    | Build any host closure (substitute `<host>`)          |
| `nix eval --accept-flake-config --json "path:.#nixosConfigurations" --apply builtins.attrNames` | List the host names available in the current checkout |
| `./build.sh`                                                                                    | Full validation + deployment                          |
| `./build.sh --host <name>`                                                                      | Target a specific host                                |
| `./build.sh --skip-all`                                                                         | Skip validation (emergency only)                      |

## Introspection

```bash
# Show high-level flake outputs
nix flake show path:. --accept-flake-config --all-systems

# Inspect aggregator keys
nix eval --accept-flake-config --json "path:.#nixosModules" --apply builtins.attrNames
nix eval --accept-flake-config --json "path:.#homeManagerModules" --apply builtins.attrNames
nix eval --accept-flake-config --json "path:.#homeManagerModules.apps" --apply builtins.attrNames

# Evaluate specific host options (substitute the host name)
nix eval "path:.#nixosConfigurations.<host>.config.boot.loader"
nix eval "path:.#nixosConfigurations.<host>.config.system.build.toplevel"
```

## External Tooling

| Tool                       | Purpose                  | Example                                     |
| -------------------------- | ------------------------ | ------------------------------------------- |
| Context7 MCP               | Documentation lookups    | Configured via `flake.lib.agents.mcp`       |
| DeepWiki MCP               | GitHub repo exploration  | Pass `owner/repo` to the DeepWiki MCP tools |
| `nix-index` / `nix-locate` | Find packaged binaries   | `nix-locate 'bin/act'`                      |
| `write-files`              | Regenerate managed files | `nix develop path:. -c write-files`         |
| `gh-actions-run`           | Local GitHub Actions     | `nix develop path:. -c gh-actions-run -n`   |

## Dev Shell Helpers

Available after `nix develop path:.`:

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

## Next Steps

- [Pattern Overview](01-pattern-overview.md) -- Dendritic fundamentals
- [Module Authoring](02-module-authoring.md) -- writing modules correctly
- [Troubleshooting](07-troubleshooting.md) -- symptoms and their resolutions
- [`../reference/local-mirrors.md`](../reference/local-mirrors.md) -- mirror paths and host enablement
