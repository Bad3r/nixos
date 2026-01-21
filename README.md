# NixOS Configuration

A NixOS configuration using the [Dendritic Pattern](https://github.com/mightyiam/infra), an organic configuration growth pattern with automatic module discovery. Powered by [flake-parts](https://flake.parts/).

## Automatic Import

All Nix files are flake-parts modules and are automatically imported via [import-tree](https://github.com/vic/import-tree). Files prefixed with `_` are omitted. No literal path imports are used, so files can be moved and nested freely.

## Build and Deployment

This project uses a custom build script, [`build.sh`](build.sh), for validation and deployment:

```bash
./build.sh              # validate and deploy
./build.sh --boot       # install for next boot only
./build.sh --update     # update flake inputs first
./build.sh --offline    # Offline build
```

The script runs a validation pipeline (format, pre-commit hooks, flake check) before deployment. It refuses to run on a dirty worktree by default; use `--allow-dirty` to override.

**Development commands:**

| Command | Description |
|---------|-------------|
| `nix develop` | Enter dev shell |
| `nix fmt` | Format files |
| `lefthook run pre-commit` | Run all hooks |

## Home Manager Package Pattern

This repo uses a dual-module approach: NixOS modules install packages, HM modules configure them. To avoid duplicate installation, HM modules set `package = null` when supported.

See the [App Modules Style Guide](docs/guides/apps-module-style-guide.md#6-create-home-manager-module) for details.

## Secrets

Secrets are managed with [sops-nix](https://github.com/Mic92/sops-nix). Encrypted payloads live in `secrets/`, a private git submodule, and are declared via `sops.secrets`.

See the [sops documentation](docs/sops/README.md) for usage instructions.

## Flake Input Deduplication

Inputs prefixed with `dedupe_` exist solely for deduplication via `.follows` declarations.

| Input | Followed By |
|-------|-------------|
| `dedupe_flake-compat` | make-shell |
| `dedupe_flake-utils` | (internal) |
| `dedupe_nur` | stylix |
| `dedupe_systems` | stylix, dedupe_flake-utils |

## Generated Files

The following files are defined in Nix and generated via [mightyiam/files](https://github.com/mightyiam/files) using `nix develop -c write-files`:

- `.actrc`
- `.gitignore`
- `.sops.yaml`
- `README.md`
- `lefthook.yml`
- `scripts/lefthook-rc.sh`

