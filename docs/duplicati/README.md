# Duplicati R2 Backups

Maintainer reference for the duplicati-r2 NixOS service: encrypted client-side backups that ship to a single Cloudflare R2 bucket via the S3-compatible API. The module turns a SOPS-encrypted manifest into per-target systemd timers at activation time, so the plaintext schedule and paths never enter the Nix store or Git.

## Architecture

```
secrets/duplicati-r2.yaml          (encrypted credentials)
secrets/duplicati-config.json      (encrypted manifest, sops binary mode)
            |
            | sops-nix templates (restartUnits = generator)
            v
/etc/duplicati/r2.env              (mode 0400, runtime credentials)
/run/duplicati-r2/config.json      (mode 0400, plaintext manifest)
            |
            | duplicati-r2-generate-units.service (oneshot, on activation)
            v
/run/systemd/system/duplicati-r2-backup-<slug>.{service,timer}
/run/systemd/system/duplicati-r2-verify-<slug>.{service,timer}
            |
            | systemd timers
            v
duplicati-cli backup|test  ->  s3://<bucket>/<host>/<slug>/
```

The generator is the only piece that runs at activation. After it exits, all backup and verify execution flows through plain systemd timers calling `duplicati-cli` with credentials sourced from the env file. State (per-target SQLite metadata) lives under `services.duplicati-r2.stateDir` and is the canonical source of truth for what is on R2.

Two operator-facing CLIs read this state without invoking `duplicati-cli`:

- `duplicati-r2-list` (Cut A): read-only path/snapshot/history/grep queries directly against the per-target SQLite. No R2 access, no AES decryption. See [operations.md](operations.md#query-the-local-sqlite-read-only).
- `duplicati-r2-extract` (Cut B): single-file or glob-mode extract that fetches only the dblocks the file needs from R2 (or a `file://` mirror), decrypts them in process memory through `pyAesCrypt`, and writes plaintext to a destination file, stdout, or an output directory. See [operations.md](operations.md#extract-a-single-file-from-r2-cut-b).

Both are auto-installed on every host where `services.duplicati-r2.stateDirReadableBy` is non-empty. The full design lives in [`../drafts/duplicati-r2-readonly-mount-investigation.md`](../drafts/duplicati-r2-readonly-mount-investigation.md); Cut C (read-only FUSE mount) is deferred there.

## Repository layout

| Path                                  | Role                                                                                                                                                                                               |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `modules/services/duplicati-r2.nix`   | Service module: options, manifest handling, generator/backup/verify scripts, sops template wiring. Exported as `flake.nixosModules."duplicati-r2"` and `flake.nixosModules.services.duplicati-r2`. |
| `modules/storage/duplicati-r2.nix`    | Re-export under the storage namespace (`flake.nixosModules.storage.duplicati-r2`).                                                                                                                 |
| `modules/apps/duplicati-r2-tools.nix` | Apps module that installs `duplicati-r2-list` and `duplicati-r2-extract` on PATH; auto-enables when `services.duplicati-r2.stateDirReadableBy` is non-empty.                                       |
| `modules/<host>/duplicati.nix`        | Per-host wiring: gates `services.duplicati-r2.enable` on the presence of both encrypted secrets, sets `stateDirReadableBy` from `metaOwner.username`.                                              |
| `packages/duplicati-r2-tools/`        | Source for the operator-facing CLIs (`duplicati-r2-list`, `duplicati-r2-extract`) plus the local `pyAesCrypt` derivation and the synthetic AES test fixture generator.                             |
| `secrets/duplicati-r2.yaml`           | SOPS-encrypted credentials (R2 keys + duplicati passphrase).                                                                                                                                       |
| `secrets/duplicati-config.json`       | SOPS-encrypted manifest in binary mode (the entire JSON manifest is the encrypted payload).                                                                                                        |
| `scripts/validate-oncalendar.sh`      | Lints `OnCalendar` expressions via `systemd-analyze calendar`.                                                                                                                                     |

## Documentation index

| File                           | Read when                                                                                                                        |
| ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| [reference.md](reference.md)   | Looking up an option, manifest field, or runtime path.                                                                           |
| [operations.md](operations.md) | Adding/editing/disabling a target, restoring, scheduling, post-deploy verification.                                              |
| [recovery.md](recovery.md)     | A backup is failing, dblocks are missing, or impact analysis is required.                                                        |
| [security.md](security.md)     | Rotating credentials, reviewing the threat model, evaluating the R2 bucket lifecycle policy, or auditing state directory access. |

Cross-reference: the host composition pattern that imports this module is described in [../architecture/05-host-composition.md](../architecture/05-host-composition.md).

Upstream documentation: the [`duplicati/documentation`](https://github.com/duplicati/documentation) source is mirrored locally at `/data/git/duplicati-documentation` for offline lookup of `duplicati-cli` flags, manifest fields, and the backup format. Sync is managed per host via `programs.gitMirror.repos`; see [../reference/local-mirrors.md](../reference/local-mirrors.md).

## Operating invariants

- One R2 bucket holds backups for every host. Per-host isolation is by prefix (`<host>/`), per-target isolation is by sub-prefix (`<slug>/`).
- The encrypted manifest is shared across hosts. Targets whose source path does not exist on a given host fail loudly with `SourceIsMissing` rather than silently writing under that host prefix.
- Disabling a target (`enable: false` in the manifest) is the supported reversible mechanism. The generator removes its units on the next activation; remote backups stay intact.
- The duplicati passphrase is per-archive. Rotating it abandons every existing backup. Treat it as immutable for the life of the bucket.
- The R2 bucket's "abort incomplete multipart uploads" lifecycle rule has been deleted on the duplicati R2 bucket. Do not reinstate without weighing it against the data-loss case described in [security.md](security.md).
