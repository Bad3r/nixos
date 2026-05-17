# Duplicati R2 Recovery

Failure modes, repair flow, and the impact-analysis playbook for missing or damaged remote volumes. Apply these procedures only after redacting the failure to a specific cause; blind `repair` runs are safe but slow.

## Failure modes

| Symptom (journal)                   | Meaning                                                                                                                                                                                       | First response                                                                                                                               |
| ----------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `SourceIsMissing`                   | The source path declared in the manifest does not exist on the host.                                                                                                                          | Confirm the source mount/path. If permanently gone, set `enable: false` on the target (see [operations.md](operations.md#disable-a-target)). |
| `MissingRemoteFiles`                | The local DB references one or more `*.dblock`/`*.dindex` objects that R2 no longer has.                                                                                                      | Run `repair` (see below). If repair cannot rebuild every missing volume, fall through to `list-broken-files` + `purge-broken-files`.         |
| HMAC-SHA256 verification failure    | A remote volume is truncated, mangled, or corrupted in transit. The AES Crypt wrapper is AES-256-CBC + HMAC-SHA256 (Encrypt-then-MAC); a damaged byte in the ciphertext flips the final HMAC. | Same as `MissingRemoteFiles`. Duplicati treats damaged volumes as missing because partial-block recovery is not supported.                   |
| `Failed OnCalendar` (generator log) | The schedule string is invalid.                                                                                                                                                               | Validate with `scripts/validate-oncalendar.sh '<expr>'`, fix the manifest, redeploy.                                                         |
| `missing environment file ...`      | `/etc/duplicati/r2.env` was not produced.                                                                                                                                                     | Confirm the credentials sops secret exists and the host module imports `sops-nix` before the duplicati module.                               |
| Generator exits non-zero            | Timer enable or start failed.                                                                                                                                                                 | Inspect `journalctl -u duplicati-r2-generate-units.service`; the unit name appears in the error line.                                        |

## Repair flow

`duplicati-cli repair <dest>` recreates missing or corrupted volumes from local source. Per-block hashes in the SQLite DB drive the rebuild: every block is identified by SHA-256, so duplicati walks the source paths, hashes 1 MiB chunks, and any chunk whose hash matches a missing block is repacked into a new dblock that is then re-uploaded.

A volume is fully repairable only when every constituent block can be located in still-present source data. Partial repair is not a thing: the new volume must produce the same encrypted bytes, which requires the same blocks in the same order.

```bash
sudo bash <<'REPAIR'
set -euo pipefail
set -a
. /etc/duplicati/r2.env
set +a

# duplicati's S3 backend reads credentials from AUTH_USERNAME / AUTH_PASSWORD.
# Without these, the operation fails with `S3NoAmzUserID: No S3 userID given`.
export AUTH_USERNAME="$AWS_ACCESS_KEY_ID"
export AUTH_PASSWORD="$AWS_SECRET_ACCESS_KEY"

dest="s3://${R2_BUCKET}/$(hostname --short)/<slug>?use-ssl=true&s3-ext-disablehostprefixinjection=true&s3-disable-chunk-encoding=true&s3-client=minio&s3-server-name=${R2_S3_ENDPOINT}"

duplicati-cli repair "$dest" --passphrase="$DUPLICATI_PASSPHRASE"
REPAIR
```

If repair completes cleanly, the next scheduled backup proceeds normally.

## When repair cannot help

If the source is gone or only partially present, repair logs which volumes it could not rebuild and exits with the affected files still marked broken in the snapshot. The supported escape hatch:

```bash
# 1. Enumerate which file paths are unrecoverable.
duplicati-cli list-broken-files "$dest" --passphrase="$DUPLICATI_PASSPHRASE"

# 2. Rewrite affected dlist files, removing broken entries from the snapshot.
duplicati-cli purge-broken-files "$dest" --passphrase="$DUPLICATI_PASSPHRASE"
```

`purge-broken-files` does not delete remote volumes by itself; orphan dblocks become eligible for the next compact pass. After it succeeds, regular `restore` works for everything else without the missing-file error.

The remote archive remains usable. The damaged paths are simply removed from the snapshot manifest. There is no way to recover the bytes themselves once both the remote volumes and the source are gone.

## DB-driven impact analysis

When a `MissingRemoteFiles` error names specific volumes, the per-target SQLite database can map them back to the affected source paths without needing to run repair. This is the same procedure that identified the two lost dblocks documented in [security.md](security.md#bucket-lifecycle-caveat).

Per-target databases live at `<services.duplicati-r2.stateDir>/duplicati-r2-<slug>.sqlite`. For ad-hoc impact analysis (where there is no concurrent writer because backups are paused or the host is in recovery mode), open them with `immutable=1` to skip lock acquisition and WAL replay entirely:

> Note: this differs from `duplicati-r2-list` and `duplicati-r2-extract`, which use `mode=ro` only (no `immutable=1`) so they can read live state alongside an active duplicati instance. `immutable=1` is correct for forensic snapshots, not for the live DB.

```bash
DB="file:/var/lib/duplicati-r2/duplicati-r2-<slug>.sqlite?mode=ro&immutable=1"

# Step 1. Find the Remotevolume IDs of the missing volumes.
sqlite3 -header "$DB" "
  SELECT ID, Name, Type, Size, State
  FROM Remotevolume
  WHERE State IN ('Uploaded', 'Verifying')
     OR Name IN ('<volume>.dblock.zip.aes', '<other>.dblock.zip.aes');
"
```

`State='Uploaded'` (without ever advancing to `Verified`) is the diagnostic signature of a multipart upload that was started but never confirmed. `Verified` rows match the objects currently on R2.

```bash
# Step 2. Map missing volumes to their affected source files.
sqlite3 -header "$DB" "
  WITH missing AS (
    SELECT ID FROM Remotevolume
    WHERE Name IN ('<volume>.dblock.zip.aes', '<other>.dblock.zip.aes')
  ),
  bad_blocks AS (
    SELECT ID FROM Block WHERE VolumeID IN (SELECT ID FROM missing)
  ),
  bad_blocksets AS (
    SELECT DISTINCT BlocksetID FROM BlocksetEntry WHERE BlockID IN (SELECT ID FROM bad_blocks)
  )
  SELECT
    f.Path,
    bs.Length AS file_size,
    (SELECT COUNT(*) FROM BlocksetEntry be WHERE be.BlocksetID = f.BlocksetID) AS total_blocks,
    (SELECT COUNT(*) FROM BlocksetEntry be
       WHERE be.BlocksetID = f.BlocksetID
         AND be.BlockID IN (SELECT ID FROM bad_blocks)) AS bad_blocks
  FROM File f
  JOIN Blockset bs ON bs.ID = f.BlocksetID
  WHERE f.BlocksetID IN (SELECT BlocksetID FROM bad_blocksets);
"
```

The output row count is the exact number of damaged paths, and the `bad_blocks / total_blocks` ratio shows the fraction of each file that is unrecoverable. Files with a low ratio (often a single MiB block out of thousands) might still be salvageable as zero-padded artifacts, but duplicati's standard `restore` will refuse to write them. Use `purge-broken-files` to clean up the snapshot, then restore the rest.

## Verification

`services.duplicati-r2.verify` enables shared verification timers for every backup target. The unit calls `duplicati-cli test <dest> --samples=<n>` on each `verify.onCalendar` tick, downloads `n` random volumes, and checks their hashes plus the HMAC-SHA256 tag of the AES Crypt wrapper. Failures surface as exit-code-1 in the journal long before the next backup attempt.

Recommended cadence:

| Cadence   | Use case                                                                 |
| --------- | ------------------------------------------------------------------------ |
| `daily`   | Active targets where loss of a recent dblock should page within the day. |
| `weekly`  | Default for long-retention archives.                                     |
| `monthly` | Cold archives with low write rate.                                       |

Sample count rule of thumb: 200 samples is enough to catch ~0.5% volume corruption with high probability over a few cycles. Increase for paranoia, lower for bandwidth.

## When the local DB is the problem

Catastrophic DB corruption (file removed, drive replaced, inconsistent state after a crash) is fixable from R2 alone:

```bash
sudo bash <<'RECREATE'
set -euo pipefail
set -a
. /etc/duplicati/r2.env
set +a

# duplicati's S3 backend reads credentials from AUTH_USERNAME / AUTH_PASSWORD.
# Without these, the operation fails with `S3NoAmzUserID: No S3 userID given`.
export AUTH_USERNAME="$AWS_ACCESS_KEY_ID"
export AUTH_PASSWORD="$AWS_SECRET_ACCESS_KEY"

dest="s3://${R2_BUCKET}/$(hostname --short)/<slug>?use-ssl=true&s3-ext-disablehostprefixinjection=true&s3-disable-chunk-encoding=true&s3-client=minio&s3-server-name=${R2_S3_ENDPOINT}"

# Move the damaged DB aside (do not delete; useful for forensics).
ts=$(date -u +%Y%m%d-%H%M%S)
mv /var/lib/duplicati-r2/duplicati-r2-<slug>.sqlite \
   /var/lib/duplicati-r2/backup-duplicati-r2-<slug>-${ts}.sqlite

duplicati-cli repair "$dest" --passphrase="$DUPLICATI_PASSPHRASE"
RECREATE
```

`repair` against a missing DB rebuilds it from the dlist and dindex files on R2. This is the heaviest recovery path and downloads every index file in the archive, plan accordingly.

## Single-file recovery from R2

For ad-hoc recovery of one file (or a small glob set) against a multi-TiB archive that cannot be fully restored on the host, use `duplicati-r2-extract` instead of `duplicati-cli restore`. It fetches only the dblocks containing the file's content blocks and decrypts them in process memory; plaintext goes only to the operator-chosen sink. Full surface and worked example: [`operations.md`](operations.md#extract-a-single-file-from-r2-cut-b).

```bash
# Recover one path to a local file.
duplicati-r2-extract <slug> /abs/path --output /tmp/recovered

# Recover by glob (mirrors snapshot tree under --output-dir).
duplicati-r2-extract <slug> --include '*.torrent' --output-dir /tmp/torrents
```

`duplicati-cli restore` remains the bulk-restore path.
