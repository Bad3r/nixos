# Logseq Nightly Workflow

Logseq is no longer built locally from the `/home/vx/git/logseq` checkout. Nightly
artifacts are produced by the `nix-logseq-git-flake` GitHub repository and published
as GitHub Releases. Hosts download the pre-built Electron bundle and wrap it in an
FHS environment supplied by the flake.

## Nightly Build Pipeline

1. **GitHub Actions (00:00 UTC)**
   - Clones the official `logseq/logseq` repository at `master`.
   - Runs the upstream build flow (`yarn install`, `npx gulp build`, `yarn cljs:release-electron`, `yarn electron:make`).
   - Packages `Logseq-linux-x64` into `logseq-linux-x64-<rev>.tar.gz`.
   - Creates or updates the release `nightly-YYYYMMDD` and uploads the tarball.
   - Updates `data/logseq-nightly.json` in the flake repo with the release tag, SRI hash, upstream revision, and publish timestamp.
   - Runs `nix fmt`, `nix flake check`, `nix build .#logseq`, and `nix run .#logseq -- --version` before committing the manifest update.

2. **Flake Manifest**
   - `data/logseq-nightly.json` always tracks the latest successful nightly release.
   - The `packages.logseq` derivation fetches the tarball via the manifest, installs it under `$out/share/logseq`, and wraps the binary with an FHS env.

## Host Integration

- The productivity role enables `services.logseq` which:
  - Installs the flake package and desktop entry.
  - Runs a systemd `logseq-sync.service` as the owner user.
  - The service calls `nix build <flake>#logseq --print-out-paths` and emits structured JSON logs.
  - `logseq-sync.timer` defaults to 02:00 UTC (two hours after the nightly release) and rebuilds only when the manifest hash changes.

- The service resolves the build directory automatically:
  - `$HOME/nixos` if present for the owner user.
  - `/etc/nixos` otherwise.
  - If neither exists, the service logs an error and exits.

## Manual Maintenance

- To force an update immediately, run `systemctl --user start logseq-sync.service` (or start the system-level unit if configured).
- To inspect logs, use `journalctl -u logseq-sync.service` (or `--user-unit` for user services).
- The `logseq` command is provided on `$PATH` by the flake package and launches the downloaded bundle inside the wrapped FHS environment.
- Source checkouts under `/home/vx/git/logseq` are no longer required for day-to-day use.
