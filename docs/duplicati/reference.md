# Duplicati R2 Reference

Complete option surface, manifest schema, and runtime artifact catalog for `services.duplicati-r2`. Source of truth: `modules/services/duplicati-r2.nix`.

## services.duplicati-r2

| Option               | Type                     | Default                 | Notes                                                                                                                                                                                  |
| -------------------- | ------------------------ | ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `enable`             | bool                     | `false`                 | Master toggle for the service.                                                                                                                                                         |
| `package`            | package                  | `pkgs.duplicati`        | Provides `duplicati-cli`.                                                                                                                                                              |
| `configFile`         | nullOr path              | `null`                  | Path to a SOPS-encrypted manifest. When set, the manifest is decrypted via a sops template into `/run/duplicati-r2/config.json`. When `null`, the manifest is rendered from `targets`. |
| `environmentFile`    | path                     | `/etc/duplicati/r2.env` | Rendered dotenv with credentials, mode 0400. Path appears in the manifest so the helper scripts can locate it.                                                                         |
| `stateDir`           | path                     | `/var/lib/duplicati-r2` | Root for per-target SQLite metadata. Created mode 0700 root:root.                                                                                                                      |
| `stateDirReadableBy` | listOf str               | `[]`                    | Usernames granted POSIX ACL read access (immediate plus default ACL) to `stateDir` and the SQLite databases. The base mode stays 0700.                                                 |
| `bucket`             | str                      | see module default      | R2 bucket name. Used when the manifest does not override it. The literal default lives in the module source so docs do not duplicate the production identifier.                        |
| `hostname`           | nullOr str               | `null`                  | Override for the `<host>` segment in the destination URL. When `null`, falls back to `config.networking.hostName`.                                                                     |
| `credentials`        | attrsOf credentialModule | nine standard keys      | Maps environment variable names to SOPS selectors.                                                                                                                                     |
| `targets`            | attrsOf targetModule     | `{}`                    | Inline target definitions. Required when `configFile` is `null`.                                                                                                                       |
| `verify`             | nullOr verifyModule      | `null`                  | Optional shared verification schedule applied to every target.                                                                                                                         |

## targetModule

| Option        | Type        | Default  | Notes                                                                                                                                                                |
| ------------- | ----------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `enable`      | bool        | `true`   | When `false`, the generator skips the target. No backup or verify units are emitted. Existing remote data is untouched.                                              |
| `source`      | path        | required | Absolute directory to back up.                                                                                                                                       |
| `onCalendar`  | str         | required | systemd timer expression. Validate with `scripts/validate-oncalendar.sh`.                                                                                            |
| `stateDir`    | nullOr path | `null`   | Override the per-target SQLite directory. Defaults to `<stateDir>/<targetKey>`.                                                                                      |
| `retention`   | nullOr str  | `null`   | Duplicati retention rule. `null` keeps all versions. Strings containing `:` are passed as `--retention-policy=<value>`; bare durations become `--keep-time=<value>`. |
| `extraArgs`   | listOf str  | `[]`     | Additional flags appended to the `duplicati-cli` invocation.                                                                                                         |
| `destSubpath` | nullOr str  | `null`   | Override the bucket sub-prefix. Defaults to the target key (the attribute name).                                                                                     |

## verifyModule

| Option       | Type         | Default  | Notes                                                     |
| ------------ | ------------ | -------- | --------------------------------------------------------- |
| `onCalendar` | str          | required | systemd timer expression for the per-target verify timer. |
| `samples`    | positive int | `200`    | Number of random samples passed to `duplicati-cli test`.  |

## credentialModule

| Option   | Type | Default               | Notes                                                                                                       |
| -------- | ---- | --------------------- | ----------------------------------------------------------------------------------------------------------- |
| `secret` | str  | `duplicati-r2/<NAME>` | SOPS selector for the credential. Override per-key when the encrypted file uses non-default selector names. |

The default credential set covers nine names, declared in `credentialNames` inside `modules/services/duplicati-r2.nix`:

```
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
R2_ACCOUNT_ID
R2_API_TOKEN
R2_BUCKET
R2_S3_ENDPOINT
R2_S3_ENDPOINT_URL
R2_REGION
DUPLICATI_PASSPHRASE
```

Each becomes a `sops.secrets."duplicati-r2/<NAME>"` entry sourced from `secrets/duplicati-r2.yaml`. The rendered env file concatenates them as `KEY=value` lines.

## Manifest schema

The decrypted manifest is plain JSON. Top-level keys:

```json
{
  "environmentFile": "/etc/duplicati/r2.env",
  "bucket": "<bucket>",
  "hostname": "<host>",
  "stateDir": "/var/lib/duplicati-r2",
  "targets": {
    "<slug>": {
      "enable": true,
      "path": "/abs/path/on/host",
      "onCalendar": "Tue,Fri 03:00:00",
      "retention": "12M:1M",
      "extraArgs": ["--throttle-upload=5MB"],
      "stateDir": "/var/lib/duplicati-r2/<slug>",
      "destSubpath": "<slug>"
    }
  },
  "verify": {
    "onCalendar": "weekly",
    "samples": 200
  }
}
```

| Field                        | Required | Notes                                                                             |
| ---------------------------- | -------- | --------------------------------------------------------------------------------- |
| `environmentFile`            | no       | Falls back to `services.duplicati-r2.environmentFile`.                            |
| `bucket`                     | no       | Falls back to `services.duplicati-r2.bucket`.                                     |
| `hostname`                   | no       | Falls back to `services.duplicati-r2.hostname` then `config.networking.hostName`. |
| `stateDir`                   | no       | Falls back to `services.duplicati-r2.stateDir`.                                   |
| `targets.<slug>.enable`      | no       | Default `true`. Setting `false` skips the target without removing it.             |
| `targets.<slug>.path`        | yes      | Absolute source path.                                                             |
| `targets.<slug>.onCalendar`  | yes      | Targets without `onCalendar` are skipped with a stderr warning.                   |
| `targets.<slug>.retention`   | no       | Omit (or `null`) for keep-all behavior.                                           |
| `targets.<slug>.extraArgs`   | no       | Defaults to `[]`.                                                                 |
| `targets.<slug>.stateDir`    | no       | Per-target override.                                                              |
| `targets.<slug>.destSubpath` | no       | Defaults to the slug.                                                             |
| `verify`                     | no       | Omit to disable verification timers across all targets.                           |

## Generated runtime artifacts

| Path                                                     | Owner / mode   | Created by                                                                                            | Contents                                                                                                                                                        |
| -------------------------------------------------------- | -------------- | ----------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/etc/duplicati/r2.env`                                  | root:root 0400 | sops template `duplicati-r2-env`                                                                      | `KEY=value` for every credential in `services.duplicati-r2.credentials`.                                                                                        |
| `/run/duplicati-r2/config.json`                          | root:root 0400 | sops template `duplicati-r2-manifest.json` (when `configFile` is set) or generator copy (inline mode) | Plaintext manifest used by every backup and verify run.                                                                                                         |
| `<stateDir>/duplicati-r2-<slug>.sqlite`                  | root:root 0600 | `duplicati-cli`                                                                                       | Per-target metadata DB (Block, BlocksetEntry, File, Fileset, Remotevolume, ...).                                                                                |
| `/run/systemd/system/duplicati-r2-backup-<slug>.service` | runtime        | generator                                                                                             | Oneshot calling `duplicati-r2-backup`.                                                                                                                          |
| `/run/systemd/system/duplicati-r2-backup-<slug>.timer`   | runtime        | generator                                                                                             | `OnCalendar=<schedule>`, `Persistent=true`.                                                                                                                     |
| `/run/systemd/system/duplicati-r2-verify-<slug>.service` | runtime        | generator (only when `verify` set)                                                                    | Oneshot calling `duplicati-r2-verify`.                                                                                                                          |
| `/run/systemd/system/duplicati-r2-verify-<slug>.timer`   | runtime        | generator (only when `verify` set)                                                                    | `OnCalendar=<verify.onCalendar>`.                                                                                                                               |
| `duplicati-r2-generate-units.service`                    | system unit    | module                                                                                                | Oneshot that rewrites all generated units. Triggered on activation and on changes to manifest, env file, or helper scripts (`restartTriggers`, `restartUnits`). |

## Slug normalization

Target attribute names are normalized into a slug used for both unit names and the per-target SQLite filename:

- Characters outside `[A-Za-z0-9_-]` are replaced with `-`.
- Leading and trailing `-` are stripped.
- An empty result becomes the literal string `target`.

Slugs collide deterministically: `bank/data` and `bank-data` both normalize to `bank-data`. Pick attribute names that already match the normalized form to keep manifest, units, and SQLite filenames identical.

## Bucket layout

Every backup target writes under `s3://<bucket>/<hostname>/<destSubpath>/`. The default `destSubpath` is the target slug, so a manifest entry keyed `photos` on host `<host>` lands at `s3://<bucket>/<host>/photos/`. Inside that prefix duplicati maintains its own object set (`*.dblock.zip.aes`, `*.dindex.zip.aes`, `*.dlist.zip.aes`).

## CLI tooling

`pkgs.duplicati-r2-tools` is an attrset of operator-facing CLIs that consume the per-target SQLite without touching R2. The service module auto-enables every member through `programs.duplicati-r2-tools.extended.enable` whenever `services.duplicati-r2.stateDirReadableBy` is non-empty.

| Attribute                         | Binary                 | Read scope                                                                                                                                                 | Cut |
| --------------------------------- | ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | --- |
| `pkgs.duplicati-r2-tools.list`    | `duplicati-r2-list`    | Per-target SQLite at `<stateDir>/duplicati-r2-<slug>.sqlite`, opened `mode=ro` (concurrent reader; URI percent-encoded).                                   | A   |
| `pkgs.duplicati-r2-tools.extract` | `duplicati-r2-extract` | Per-target SQLite (`mode=ro`), R2 GETs (read-only) for the dblocks the requested file needs, AES decrypt in process memory, on-disk encrypted-block cache. | B   |

`duplicati-r2-list` accepts the slug as a positional argument, resolves `<stateDir>` via `/run/duplicati-r2/config.json` (overridable with `--config` or `--db`), and never opens an R2 connection or AES decryption path. Operator workflow and full subcommand surface live in [`operations.md`](operations.md#query-the-local-sqlite-read-only). Design rationale: [`../drafts/duplicati-r2-readonly-mount-investigation.md`](../drafts/duplicati-r2-readonly-mount-investigation.md) Sections 3 (SQL schema) and 5.1 (Cut A scope).

`duplicati-r2-extract` resolves a single file (or a glob set) via the same SQLite resolver, fetches only the dblocks containing the file's content blocks from R2 (or a `file://` mirror), decrypts them through `pyAesCrypt`, and writes plaintext to a destination file, stdout, or an output directory. Plaintext never persists outside the operator-chosen sink. Operator workflow and full flag surface live in [`operations.md`](operations.md#extract-a-single-file-from-r2-cut-b). Design rationale: [`../drafts/duplicati-r2-readonly-mount-investigation.md`](../drafts/duplicati-r2-readonly-mount-investigation.md) Sections 4 (end-to-end design) and 5.2 (Cut B scope).

Cut C (read-only FUSE mount) is not implemented; the `pkgs.duplicati-r2-tools.mount` namespace is reserved so it can land without renaming.

## Operation pipeline

1. sops-nix decrypts `secrets/duplicati-r2.yaml` and (if `configFile` is set) `secrets/duplicati-config.json` during activation.
2. Templates render `/etc/duplicati/r2.env` and `/run/duplicati-r2/config.json`. Both templates set `restartUnits = [ "duplicati-r2-generate-units.service" ]`, so any change triggers regeneration.
3. `duplicati-r2-generate-units.service` runs once: cleans up old runtime units, parses the manifest, emits new backup and verify units for every enabled target with a valid `onCalendar`, then `systemctl daemon-reload`s and enables the timers with `--runtime`.
4. Timers fire on schedule, calling `duplicati-r2-backup` (or `duplicati-r2-verify`), which sources the env file and shells out to `duplicati-cli`.
5. `duplicati-cli` updates its per-target SQLite DB and uploads or verifies objects on R2.
