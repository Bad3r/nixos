# Duplicati R2 read-only mount investigation

Investigation closing GitHub issue [#204](https://github.com/Bad3r/nixos/issues/204): "investigate(duplicati): read-only mount for encrypted R2 backup archives".

The output is a design decision, not an implementation. Recommendation is at the end.

## TL;DR

- **Build Cut A** (path-listing CLI from local SQLite, no decryption): low cost, no crypto dependency, immediate forensic value, reuses `services.duplicati-r2.stateDirReadableBy`.
- **Build Cut B** (single-file extract by path with on-demand R2 fetch + decrypt): solves the original "read one file without a full restore" problem at a fraction of the implementation cost of FUSE.
- **Defer Cut C** (read-only FUSE mount): real but bounded benefit; cost dominates because the FS-semantics layer (open/read/release lifecycle, partial-range reads, caching policy) is most of the work and Cut B already covers the common operator workflow.
- **Reject** any approach that re-derives metadata from R2 instead of reusing the per-target SQLite databases. Recreate-from-remote is heavy (`repair` against a missing DB downloads every dindex) and the local DB is already exposed by the `stateDirReadableBy` ACL.

**Local-storage budget**: none of the three cuts requires downloading the full archive. Cut A is zero-byte-ingress (reads only the local SQLite that already exists on disk). Cut B and Cut C download exactly the dblocks needed to satisfy the active read; the encrypted-dblock cache is bounded and configurable (default 1 GiB). See [Section 9](#9-storage-budget).

## Investigation scope

The investigation answers six questions from issue #204:

1. Is there prior art that already decrypts the dblock format outside `duplicati-cli`?
2. What is the precise on-the-wire format (encryption wrapper, dindex, dlist, dblock)?
3. Which SQLite tables resolve `(path, snapshot)` to `(volume, offset, length)`, and is `mode=ro&immutable=1` against the live state directory safe?
4. What does the end-to-end design look like (credentials, fetcher, decrypt, zip, FUSE, lifecycle)?
5. What is the smallest useful cut?
6. What are the build/defer/reject criteria?

Each section below cites upstream source by file and symbol; line numbers are deliberately omitted because they drift across releases.

## 1. Prior art

### 1.1 Upstream feature request: still open, no implementation

GitHub issue [duplicati/duplicati#3081](https://github.com/duplicati/duplicati/issues/3081) ("Mount backups as real folders", March 2018) is the standing request for a FUSE filesystem and remains open. Upstream maintainer commentary ([@kenkendk](https://github.com/duplicati/duplicati/issues/3081#issuecomment-369769921)) confirms the architecture sketch:

- Directory listing from the local DB is fast (single SQL query per directory).
- File reads are slow because the format is built around batch fetches and most filesystem reads ask for one file at a time.
- A workable design is a FUSE process in any language plus a long-running C# helper (`Duplicati.FuseSupport.exe`) that performs the crypto and zip work over stdin/stdout.

No FUSE driver has been merged. The companion request for an in-browser file preview (forum thread "Open File from History/See File Content") has the same status.

### 1.2 Official `RestoreFromPython` script

`Tools/Commandline/RestoreFromPython/restore_from_python.py` in the upstream repo is the closest precedent for an in-language reader. Properties:

- Pure Python, no .NET dependency.
- Dependencies: [`pyAesCrypt`](https://github.com/marcobellaccini/pyAesCrypt), `ijson`, `zipfile`, `sqlite3`, `hashlib`, plus stdlib helpers.
- Reads dlist, dindex, and dblock files directly from a local folder (no R2 fetcher).
- Builds its own SQLite index (`py-restore-index.sqlite`) by parsing the dindex JSON files; does not consume Duplicati's local DB.
- Streams JSON via `ijson` to avoid loading the full filelist for large archives.
- Supports glob filters, so a single-path restore is already in-scope.
- Memoised dblock cache (default 200 MiB) bounds memory.
- Cannot read GPG-encrypted backups; AES (.aes) only.

This script proves three things at once: (a) the dblock/dindex/dlist parsing is tractable in Python in a few hundred lines; (b) a single-file restore is achievable without downloading every volume; (c) Duplicati's own local DB is not strictly required.

### 1.3 Rust forks (decrypt-incomplete)

- [`nmccarty/Rust-Duplicati-Restore`](https://github.com/nmccarty/Rust-Duplicati-Restore) and the optimisation fork [`7ERr0r/duplicati-restore-rs`](https://github.com/7ERr0r/duplicati-restore-rs).
- Last activity January 2023 (v0.0.6.1).
- Multi-threaded zip reader (`zip-duplicati`) but explicitly **does not support `.aes` encryption**. Operationally useless against a Duplicati R2 archive without a separate decryption pass.

### 1.4 AES Crypt File Format third-party libraries

Duplicati's encryption wrapper is the public, specified [AES Crypt File Format](https://www.aescrypt.com/aes_stream_format.html). Multiple third-party readers exist:

| Language | Library                                                                                     | Format versions | Maintained                                        |
| -------- | ------------------------------------------------------------------------------------------- | --------------- | ------------------------------------------------- |
| Python   | [`pyAesCrypt`](https://github.com/marcobellaccini/pyAesCrypt) (used by `RestoreFromPython`) | v2 only         | Inactive (no release in 12+ months as of writing) |
| Rust     | [`aescrypt-rs`](https://crates.io/crates/aescrypt-rs)                                       | v0..v3          | Actively maintained                               |
| Go       | [`andreacioni/aescrypt`](https://pkg.go.dev/github.com/andreacioni/aescrypt)                | v1, v2          | Light-touch                                       |
| Dart     | [`alexgoussev/aes_crypt`](https://github.com/alexgoussev/aes_crypt)                         | v2              | Active                                            |

`pyAesCrypt` covers the format produced by Duplicati today (v2 default). Duplicati 2.3.0.101 added optional v3 output behind `DUPLICATI__AES_VERSION=3`; if v3 is ever turned on, switching to `aescrypt-rs` (or contributing v3 support to `pyAesCrypt`) is the migration path.

### 1.5 Comparable tools in adjacent backup ecosystems

- **Borg**: ships `borg mount` natively (FUSE).
- **Restic**: `restic mount` is in stable releases.
- **Duplicacy**: still requesting FUSE ([gilbertchen/duplicacy#7](https://github.com/gilbertchen/duplicacy/issues/7)).
- **rclone mount**: cross-platform via WinFsp; not relevant because rclone exposes encrypted volumes, not the snapshot tree.

### 1.6 Conclusion

There is no off-the-shelf FUSE driver to import. There is a usable Python reference (`RestoreFromPython`) for the dblock/dindex/dlist parser and an actively maintained AES Crypt library in Rust. Cut A and Cut B can be built on existing libraries with no novel cryptography. Cut C requires writing the FUSE layer from scratch.

## 2. On-the-wire format

### 2.1 Filename grammar

From `Duplicati/Library/Main/Volumes/VolumeBase.cs:ParseFilename`:

```
<prefix>-((b|i)<guid> | <YYYYMMDDTHHMMSSZ>).(dblock|dindex|dlist).<compression>[.<encryption>]
```

- `b<guid>` = block volume, `i<guid>` = index volume.
- Timestamp variant only on dlist.
- Default compression module is `zip`; default encryption module is `aes`.
- The `aes` extension on R2 indicates the AES Crypt File Format wrapper.

The slug under `s3://<bucket>/<host>/<slug>/` (set by `services.duplicati-r2.targets.<key>.destSubpath`) holds three families: `*.dblock.zip.aes`, `*.dindex.zip.aes`, `*.dlist.zip.aes`.

### 2.2 Encryption wrapper: AES Crypt File Format v2 (default), v3 (opt-in)

Source of truth: `duplicati/sharpaescrypt:src/Constants.cs` and `src/SetupHelper.cs`.

**Algorithm**: AES-256-CBC with `PaddingMode.None` (Encrypt-then-MAC); HMAC-SHA256 throughout. **Not AES-GCM**.

**Constants** (from `Constants.cs`):

```text
MAGIC_HEADER          = "AES" (3 bytes)
MAX_FILE_VERSION      = 3
MIN_FILE_VERSION      = 0
BLOCK_SIZE            = 16 (AES block in bytes)
IV_SIZE               = 16
KEY_SIZE              = 32 (AES-256)
HMAC_SIZE             = 32 (SHA-256 output)
KEY_HASH_ITERATIONS   = 8192   (legacy v0..v2 KDF, hardcoded by AES Crypt spec)
KDF_MIN_ITERATIONS    = 10_000      (v3 PBKDF2 lower bound)
KDF_MAX_ITERATIONS    = 1_200_000   (v3 PBKDF2 upper bound)
```

**Key derivation**:

- v0..v2 (`SetupHelper.GenerateHeaderKeyUsingLegacy`): UTF-16LE-encoded password concatenated with the 16-byte header IV, hashed by SHA-256 a total of 8192 times. Output is the 32-byte header key.
- v3 (`SetupHelper.GenerateHeaderKeyUsingPBKDF2`): PBKDF2 with HMAC-SHA512 PRF; password is UTF-8; salt is the 16-byte header IV; iteration count read from a 4-byte big-endian field in the file header (range enforced by `KDF_MIN_ITERATIONS`/`KDF_MAX_ITERATIONS`).

**Layout (high-level, all versions)**:

```
"AES"                  # 3 bytes
version                # 1 byte (0..3)
reserved/mod           # 1 byte (0x00 in v0/v1; ciphertext-len mod 16 in v2)
extensions (v1+)       # TLV list, each entry = 2-byte length + tag\0 + value;
                       # terminated by length 0x0000
header IV              # 16 bytes (also doubles as PBKDF2 salt in v3)
[v3 only] iter count   # 4 bytes big-endian
encrypted bulk IV+KEY  # 48 bytes = AES-CBC(headerKey, headerIV) of (16-byte bulk IV || 32-byte bulk key)
header HMAC            # 32 bytes (HMAC-SHA256 of the 48-byte block, plus the version byte for v3)
ciphertext             # variable; AES-CBC(bulkKey, bulkIV) of the inner zip bytes
ciphertext mod         # 1 byte = inner length mod 16 (only for v2; lives in the reserved byte for v3)
final HMAC             # 32 bytes (HMAC-SHA256 of all preceding ciphertext bytes)
```

`SharpAESCrypt` adds a non-spec PKCS-style padding check before the modulo byte; the `DUPLICATI__AES_IGNORE_PADDING_BYTES=1` environment variable (read by `Duplicati.Library.Encryption.AESEncryption.GetEnvValue`, which uppercases the option key `aes-ignore-padding-bytes` and prefixes it with `DUPLICATI__`) disables it for interoperability with strict-spec implementations. Any third-party reader must accept input with or without that check.

**HMAC verification is non-optional**. `DecryptingStream.cs` requires the HMAC to match; on mismatch the implementation throws `HashMismatchException("Content has been tampered with, do not trust content: invalid HMAC")` and aborts. The mount must surface mismatches loudly (out of scope: zero-fill or partial output).

### 2.3 Duplicati zip volumes (after AES decryption)

Source: `Duplicati/Library/Main/Volumes/{BlockVolumeReader,IndexVolumeReader,FilesetVolumeReader}.cs` and `VolumeBase.cs`.

Every zip volume contains a `manifest` JSON entry at the root with at least:

```json
{
  "Version": 2,
  "Encoding": "utf8",
  "Blocksize": 102400,
  "BlockHash": "SHA256",
  "FileHash": "SHA256",
  "AppVersion": "2.0.x.y"
}
```

`Blocksize` and `BlockHash` are critical: a reader must compare them against the value used by the local DB and refuse to operate on mismatches.

**dblock layout**:

- One zip entry per data block.
- Entry name = base64url (URL-safe Base64, `-_` instead of `+/`) of the SHA-256 (or selected `BlockHash`) of the block content.
- Entry payload = the block bytes; zip's `STORE`/`DEFLATE` compression handles transport-level compression.
- No fixed offsets; reads use the central directory and `OpenRead(name)`.

**dindex layout**:

- Folder `vol/<dblock-name>` (constant `INDEX_VOLUME_FOLDER`): one JSON file per dblock with shape `{ blocks: [{ hash, size }, ...], volumehash, volumesize }`.
- Folder `list/<blocklist-hash-base64url>` (constant `INDEX_BLOCKLIST_FOLDER`): one entry per blocklist; payload is the concatenation of fixed-width block-hash bytes (raw bytes of the configured `BlockHash`).
- The dindex is the on-the-wire representation of "what blocks each dblock contains" plus "which blocklists exist". A reader can rebuild the entire `Block`/`Blockset` lookup table from dindex files alone; this is exactly what `repair` does when the local DB is missing.

**dlist layout**:

- `manifest`: same JSON header.
- `filelist.json`: streaming JSON array of file entries. Per-entry fields: `path`, `type` (`File`, `Folder`, `Symlink`, etc.), `size`, `hash` (full-file hash), `time` (mtime), `metahash`, `metasize`, optionally `blocklists` (array of blocklist hashes for files larger than `Blocksize`) or `blocklisthash` (single hash for medium files).
- `extra/` (folder constant `CONTROL_FILES_FOLDER` in `VolumeBase.cs`): rare; control files attached to a snapshot.

**Files smaller than `Blocksize`**: `hash` references the single content block directly. **Files larger**: `blocklists[i]` references a blocklist entry that decompresses to the ordered concatenation of content-block hashes. Each block hash then resolves to a dblock entry.

### 2.4 Read amplification

A `read(offset, length)` for a file backed by `n` blocks at default settings (`Blocksize=100 KiB`, `dblock-size=50 MiB`) touches at most `n` distinct dblocks but typically fewer because dedup clusters. For large reads the layout is friendly to range fetches: a 50 MiB sequential read averages a single dblock per file, not 500. The cache policy in any implementation should be "evict whole dblocks", not block-level.

## 3. SQLite path-to-bytes

### 3.1 Tables required

Schema source: `Duplicati/Library/Main/Database/Database schema/Schema.sql` (current version `19`). Relevant tables and the path-to-bytes responsibility of each:

| Table                                               | Role                                                                                                                                                                      |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Remotevolume`                                      | One row per remote object. `Name`, `Type` (`Files`/`Blocks`/`Index`), `Size`, `Hash`, `State`. Foreign-key target for `Block.VolumeID` and `Fileset.VolumeID`.            |
| `Fileset`                                           | One row per snapshot (one dlist). `VolumeID` -> `Remotevolume.ID`, `Timestamp`, `IsFullBackup`.                                                                           |
| `FilesetEntry`                                      | Many-to-many `Fileset` <-> `File`. `Lastmodified` is the file mtime at scan.                                                                                              |
| `PathPrefix` + `FileLookup` (joined as `File` view) | Path lookup. `File.BlocksetID` is the file's content blockset; `File.MetadataID` -> `Metadataset`. The view rewrites paths as `Prefix \|\| Path` to deduplicate prefixes. |
| `Blockset`                                          | One row per unique content stream. `Length` = full-file size (or metadata blob size); `FullHash` = file hash.                                                             |
| `BlocksetEntry`                                     | Ordered block list inside a blockset; `(BlocksetID, Index, BlockID)`.                                                                                                     |
| `Block`                                             | One row per unique block. `Hash`, `Size`, `VolumeID`. `BlockHashSize` index keys lookups.                                                                                 |
| `BlocklistHash`                                     | For very large blocksets where the block list is itself stored as blocks: ordered list of blocklist hashes per blockset.                                                  |
| `Metadataset`                                       | Per-file metadata blob (timestamps, attrs); itself a blockset.                                                                                                            |

### 3.2 Canonical SQL for a single-file read

```sql
-- Inputs: bind :path and :version_id (Fileset.ID) at preparation.
-- Output: ordered (Block.Hash, Block.Size, Remotevolume.Name) per data block.
SELECT
  b.Hash      AS block_hash,        -- base64url-decode for the zip entry name
  b.Size      AS block_size,
  rv.Name     AS volume_name        -- e.g. duplicati-bABC123...dblock.zip.aes
FROM File f
  JOIN FilesetEntry fse ON fse.FileID    = f.ID
  JOIN BlocksetEntry be ON be.BlocksetID = f.BlocksetID
  JOIN Block         b  ON b.ID          = be.BlockID
  JOIN Remotevolume  rv ON rv.ID         = b.VolumeID
WHERE f.Path = :path
  AND fse.FilesetID = :version_id
  AND rv.State IN ('Verified', 'Uploaded')
ORDER BY be.Index;
```

For files larger than `Blocksize` whose ordered hash list is stored in a blocklist (i.e., `BlocksetEntry` is empty for `f.BlocksetID`), the query path differs: read `BlocklistHash` rows for the blockset, fetch each blocklist entry via the matching `Block` row, and use the decoded block-hash sequence as `Block.Hash` keys. Both paths converge on `(volume_name, block_hash, block_size)` triples.

### 3.3 Snapshot enumeration

```sql
-- Latest snapshot (= max Timestamp) containing :path:
SELECT fs.ID, fs.Timestamp
FROM Fileset fs
  JOIN FilesetEntry fse ON fse.FilesetID = fs.ID
  JOIN File f           ON f.ID = fse.FileID
WHERE f.Path = :path
ORDER BY fs.Timestamp DESC
LIMIT 1;

-- All versions of :path with size and mtime:
SELECT fs.Timestamp, bs.Length AS file_size, fse.Lastmodified
FROM Fileset fs
  JOIN FilesetEntry fse ON fse.FilesetID = fs.ID
  JOIN File f           ON f.ID = fse.FileID
  JOIN Blockset bs      ON bs.ID = f.BlocksetID
WHERE f.Path = :path
ORDER BY fs.Timestamp;
```

### 3.4 Directory listing

```sql
-- Children of :parent (string with trailing slash):
SELECT
  SUBSTR(f.Path, LENGTH(:parent) + 1) AS name,
  bs.Length                            AS size,
  fse.Lastmodified                     AS mtime
FROM File f
  JOIN FilesetEntry fse ON fse.FileID    = f.ID
  JOIN Blockset bs      ON bs.ID         = f.BlocksetID
WHERE fse.FilesetID = :version_id
  AND f.Path GLOB (:parent || '*')
  AND INSTR(SUBSTR(f.Path, LENGTH(:parent) + 1), '/') = 0;
```

The `GLOB` pattern uses the path-prefix index introduced in schema migration "9. Refactor Paths.sql"; the `File` view exposes the joined path while `FileLookup` retains the prefix-deduplicated storage, so directory listings remain index-served.

### 3.5 Read-only opener safety

The `services.duplicati-r2.stateDirReadableBy` ACL appends three POSIX ACL rules (in `modules/services/duplicati-r2.nix`, `systemd.tmpfiles.rules` block):

```
A+ <stateDir>      - - - - u:<user>:rX,m::r-x,d:u:<user>:rX,d:m::r-x
A+ <stateDir>/*    - - - - u:<user>:rX,m::r-x,d:u:<user>:rX,d:m::r-x
A+ <stateDir>/*/*  - - - - u:<user>:rX,m::r-x
```

The maintainer gets read access to the SQLite file and to the WAL/SHM sidecar files `duplicati-cli` may create alongside it. The default ACL propagates `u:<user>:rX` to descendants; the kernel's create-mode mask filter would otherwise collapse the inherited mask to `---` on every newly-created mode-0600 file, so the explicit `m::r-x` and the backup script's post-run `setfacl -R -m m::r-x` keep the named-user grant effective (see §9.6). Consequences:

- `mode=ro` alone is insufficient: SQLite still wants to acquire a shared lock on the WAL, which requires write on the directory.
- `mode=ro&immutable=1` is the correct choice. SQLite skips lock acquisition and WAL replay entirely; the database is treated as a frozen snapshot.

Safety properties of `immutable=1`:

- **Cannot corrupt the DB** under any circumstance. The SQLite engine refuses writes regardless of `query_only`.
- **May read stale data** if a backup is mid-transaction. Specifically, if `duplicati-cli` is in the middle of writing a new fileset, the maintainer mount will see the pre-transaction state; rows added since the last checkpoint are invisible. This is acceptable for forensic browsing.
- **Will not see WAL-only changes**. With WAL mode, durable but uncheckpointed changes live in the `-wal` file. `immutable=1` skips WAL replay, so the mount's view lags by up to one checkpoint interval.

Recommendation: open with `file:<path>?mode=ro&immutable=1&nolock=1` and apply `PRAGMA query_only = ON;` immediately after open. Document in the operator runbook that the mount's view of the DB is the last-checkpointed state and that the mount should be unmounted before triggering a manual backup.

## 4. End-to-end design

```
+-------------------------------------------------------------------+
|             duplicati-r2-mount  (single binary or script)         |
+-------------------------------------------------------------------+
|                                                                   |
|  +---------------+   read-only   +---------------------------+    |
|  | Path resolver |---------------|  per-target SQLite DB     |    |
|  | (SQL queries) |   immutable=1 |  /var/lib/duplicati-r2/   |    |
|  +-------+-------+               +---------------------------+    |
|          | (volume_name, hash, size, range)                       |
|          v                                                        |
|  +---------------+    GetObject  +---------------------------+    |
|  | R2 fetcher    |-------------->|  R2 (s3 endpoint)         |    |
|  | (range reads) |   credentials |  via /etc/duplicati/r2.env|    |
|  +-------+-------+   from env    +---------------------------+    |
|          | encrypted bytes                                        |
|          v                                                        |
|  +---------------+   AES decrypt +---------------------------+    |
|  | Crypto layer  |<------------- |  pyAesCrypt / aescrypt-rs |    |
|  +-------+-------+ DUPLICATI_PASSPHRASE                          |
|          | inner zip bytes                                        |
|          v                                                        |
|  +---------------+   on-disk     +---------------------------+    |
|  | dblock cache  |<------------> |  $XDG_CACHE_HOME/         |    |
|  | (LRU)         |               |    duplicati-r2-mount/    |    |
|  +-------+-------+               +---------------------------+    |
|          | block bytes                                            |
|          v                                                        |
|  +-----------------------------+                                  |
|  | Output: stdout / file / FUSE|                                  |
|  +-----------------------------+                                  |
+-------------------------------------------------------------------+
```

### 4.1 Credential sourcing

Reuse `/etc/duplicati/r2.env` (the existing rendered dotenv, mode 0400 root:root). The env file already carries `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `R2_S3_ENDPOINT_URL`, `R2_REGION`, `DUPLICATI_PASSPHRASE`. The mount tool sources this file under `sudo -E` for an interactive session, or runs as a systemd unit with `EnvironmentFile=/etc/duplicati/r2.env` for an unattended mount.

Reasons not to issue a separate read-only Cloudflare key pair:

- R2 credentials cannot be scoped to a prefix without a Worker.
- The mount is read-only by tool design; the credential surface is identical to today's `duplicati-cli` usage.

The marginal benefit of a separate read-only pair is small. If desired, a follow-up issue can scope the mount to a prefix-bound Worker; this is independent of the present decision.

### 4.2 R2 fetcher with on-disk cache

- Use the same s3 client knobs as `duplicati-cli` (see `modules/services/duplicati-r2.nix` for the destination URL parameters: `use-ssl=true`, `s3-ext-disablehostprefixinjection=true`, `s3-disable-chunk-encoding=true`, `s3-client=minio`). For Python, `boto3` plus an explicit `endpoint_url` is sufficient.
- Cache encrypted dblocks on disk under `$XDG_CACHE_HOME/duplicati-r2-mount/<host>/<slug>/<volume_name>` with mode 0600. Decrypted bytes never touch disk; decryption happens streaming on each block read.
- LRU eviction with a configurable cap (default 1 GiB).
- TTL-cache the SQLite query results inside the process for the lifetime of the mount session; the DB is immutable for that session by construction (`immutable=1`).

### 4.3 AES decryption layer

- Cut A: not needed.
- Cut B/C: prefer `pyAesCrypt` for v2-compatibility today. Bind a feature flag `MOUNT_AES_VERSION=3` to swap to `aescrypt-rs` (or a v3-extended Python module) when upstream defaults change. Match the `DUPLICATI__AES_IGNORE_PADDING_BYTES=1` environment variable so the implementation accepts files written by both SharpAESCrypt and strict-spec implementations.
- Surface every HMAC mismatch as a hard `EIO` (FUSE) or stderr error (CLI). Never zero-fill; never silently truncate.

### 4.4 Zip-entry seek

- After AES decryption, the inner bytes are a standard zip archive. Python `zipfile.ZipFile(io.BytesIO(...))` plus `.read(name)` is sufficient for Cut B; for Cut C, decode the central directory once per dblock and cache the byte ranges so subsequent block reads do not re-parse the directory.
- Block-entry names are base64url of the block hash. Convert with `base64.urlsafe_b64encode(hash_bytes).rstrip(b'=').decode('ascii')` for Python; the rstrip is needed because Duplicati omits zip-name padding.

### 4.5 FUSE bindings (Cut C only)

- Linux only; macOS/FreeBSD parity is not a goal for this repo.
- `fusepy` (Python) or `fuser` (Rust) both support read-only mounts with a small surface: `getattr`, `readdir`, `open`, `read`, `release`, `readlink` for symlinks.
- One FUSE inode per `(snapshot_id, file_id)`. Inode 1 is the root; top-level directories are snapshot timestamps in `YYYYMMDDTHHMMSSZ` form.
- Permissions: expose files mode 0400, directories 0500, owner = the maintainer that started the mount. Metadata (mtime, type) comes from `FilesetEntry.Lastmodified` and `Metadataset.Content`. Do not synthesise owner/group from the source mtime metadata; the maintainer started the mount and should own everything visible.

### 4.6 Per-mount lifecycle

- `duplicati-r2-mount up <slug> <mountpoint>`: opens the SQLite DB (`mode=ro&immutable=1`), validates the `Configuration` table for matching block-hash algorithm, sources `/etc/duplicati/r2.env`, prefetches the latest dlist, mounts (Cut C) or enters interactive shell (Cut A/B).
- `duplicati-r2-mount down <mountpoint>`: `fusermount -u`, evicts the cache by default (`--keep-cache` to retain).
- Suggested unit ownership pattern: the user-level service `duplicati-r2-mount@<slug>.service` runs under `metaOwner`, mounts under `~/duplicati-mount/<slug>`, and is stopped on session logout. No system-level unit is required because the maintainer is the only consumer.

## 5. The three cuts

### 5.1 Cut A: path-listing CLI (no decryption)

**Scope**: snapshot enumeration, directory listing, single-file metadata (size, mtime, hash, snapshot history). No bytes leave R2; no AES code in the build.

**Interface sketch**:

```
duplicati-r2-list versions <slug>
duplicati-r2-list ls       <slug> [<snapshot>] <path>
duplicati-r2-list stat     <slug> [<snapshot>] <path>
duplicati-r2-list history  <slug> <path>
duplicati-r2-list grep     <slug> <pattern>           # path-glob, not content
```

**Build cost**: ~1 day. Pure SQL queries, one Python or Bash script. Test surface is fully offline (use a synthetic SQLite DB seeded by `duplicati-cli backup` against `/tmp`).

**Risk**: zero crypto risk; no R2 dependency; tool is useless on a host with no local DB (acceptable, mirrors `duplicati-cli` behaviour).

**Value**: solves a meaningful chunk of the original problem: "which file was where in which snapshot at what time" is answerable instantly without paying egress.

### 5.2 Cut B: single-file extract CLI (decrypts on demand)

**Scope**: extract one file (or a glob) from a chosen snapshot to stdout, a path, or `-`. Downloads only the dblocks needed.

**Interface sketch**:

```
duplicati-r2-extract <slug> [--snapshot <id|timestamp>] <path> [--output <dest>]
duplicati-r2-extract <slug> --include '<glob>' --output-dir <dest>
duplicati-r2-extract <slug> --diff <path> <snapA> <snapB>     # uses extract twice
```

**Build cost**: 3..5 days. Reuses Cut A's resolver. Adds R2 fetcher (boto3), AES decrypt (`pyAesCrypt`), zip seek, blocklist resolution, on-disk cache. Tested end-to-end against a small fixture archive with at least one file > `Blocksize` to exercise the blocklist path.

**Risk**:

- Upstream format drift on AES v2 -> v3 default (currently opt-in). Mitigation: support both via the AES library swap.
- Blocksize/BlockHash mismatch between the local DB and a re-imported archive. Mitigation: refuse to operate when `Configuration.blocksize` differs from the manifest in the first dlist read.
- Multipart-orphaned dblocks (`Remotevolume.State='Uploaded'` without `'Verified'`) will resolve to 404 on R2; mitigation: detect upfront via state filter and surface a clear "missing volume" error before fetch.

**Value**: solves the original problem stated in #204. Most of the operational use case (browse, grep, single-file recovery) is covered without writing a kernel filesystem.

### 5.3 Cut C: read-only FUSE mount

**Scope**: `mount` the archive at a path; standard `ls`, `cat`, `grep`, `diff` work transparently.

**Build cost**: 7..14 days additional on top of Cut B. Real cost is in the FUSE semantics layer:

- Range reads (`read(offset, len)` mid-block) require partial decompression of one zip entry plus a streaming concatenation across multiple blocks.
- Caching policy decisions: per-block (small, granular) vs per-dblock (large, simple) vs hybrid.
- Race conditions between `release` and active `read` calls.
- Symlink loops, hard-link representation, special files.
- `getxattr`/`listxattr` if the metadata blob is to be exposed.
- Test plan: `fio` random reads, `find | xargs grep` over a non-trivial archive, kernel-level `mmap` on a large file.

**Risk**:

- FUSE-on-Linux is stable; FUSE-on-macOS via macFUSE is a moving target. Linux-only is acceptable per this repo's constraints.
- A misbehaving mount can wedge a maintainer's terminal; need a `fusermount -uz` escape hatch and a clear systemd unit boundary.
- Maintenance: every Duplicati format change risks breaking the mount silently. Cut B fails loudly on the first command; Cut C fails inside a FUSE handler under load.

**Value**: matches the Borg/Restic experience. For a single-host repo with two backup targets, the marginal value over Cut B is small.

## 6. Decision criteria

| Criterion              | Weight | Cut A                            | Cut B                   | Cut C                          |
| ---------------------- | ------ | -------------------------------- | ----------------------- | ------------------------------ |
| Build cost             | high   | ~1 day                           | 3..5 days               | +7..14 days over B             |
| Format-drift risk      | high   | nil (no crypto/zip)              | low (AES v2->v3 only)   | medium (zip + FS)              |
| Maintenance over years | high   | trivial                          | small                   | recurring                      |
| Crypto risk            | high   | nil                              | low (uses ref libs)     | low (same as B)                |
| Operator value         | high   | medium (browse/grep)             | high (recover one file) | high (browse/cat)              |
| Packaging              | med    | shell script + Nix               | Python + Nix            | Python+FUSE + Nix              |
| ACL interaction        | med    | uses `stateDirReadableBy` only   | adds env-file read      | adds env-file read             |
| Bus-factor protection  | med    | high (works without crypto code) | high                    | medium (FUSE expertise needed) |

Hard constraints from issue #204 carried through:

- Read-only against R2 and the local SQLite. Cut A and Cut B respect this trivially; Cut C respects it through FUSE flags.
- No passphrase rotation. None of the cuts modify state.
- No silent zero-fill on corruption. Each cut surfaces errors via stderr/`EIO`.
- Reuse `services.duplicati-r2.stateDir`. All three cuts open the per-target SQLite via the existing ACL.

## 7. Recommendation

**Build Cut A** as a first PR. Single Python script (~150 lines) packaged as `pkgs.duplicati-r2-tools.list`, exposed through the existing `services.duplicati-r2` module. Wire it as `duplicati-r2-list <slug> ...` on `PATH` for users in `stateDirReadableBy`. No new secret surface; no R2 access; no AES code. Cut A should land before Cut B because it provides immediate ergonomic wins (snapshot-aware grep) and validates the SQLite query path against the production DBs in isolation.

**Build Cut B** as a follow-up PR after Cut A is in production for at least one verify cycle. Reuse the resolver. Add `boto3` plus `pyAesCrypt`. Package it as `pkgs.duplicati-r2-tools.extract` and reuse the env file. The crypto and fetch layers are well-trodden; the test fixture should include at least one snapshot with files at three sizes (single block, single blocklist, multi-blocklist) and one deliberately corrupted dblock to confirm the loud-failure contract.

**Defer Cut C** to a future issue. Reasons: marginal value on top of Cut B is bounded; recurring maintenance against format drift is meaningful; FUSE expertise is not currently on this repo's bus. If a future workflow demonstrates Cut B is structurally inadequate (e.g., diffing terabyte snapshots with `diff -r`), revisit.

**Reject** any approach that:

- Re-derives metadata from R2 instead of reading the local SQLite. The local DB is exactly what `services.duplicati-r2.stateDirReadableBy` exposes for this purpose.
- Caches decrypted plaintext on disk. Plaintext lives only in process memory.
- Uses a separate Cloudflare R2 token pair without a clear scoping benefit. The existing token already grants the same access surface.
- Breaks the loud-failure contract (no zero-fill on missing/corrupt blocks).

## 8. Out of scope notes

- **Write paths**: forbidden by the issue and by `docs/duplicati/security.md`.
- **Re-encryption / passphrase rotation**: forbidden by `docs/duplicati/security.md`.
- **Replacing `duplicati-cli restore`**: a mount or extract tool and a full restore are complementary. Bulk restore stays as documented in `docs/duplicati/operations.md`.
- **GPG-encrypted archives**: not in production; the design above is AES-only by intent.
- **Cross-platform**: not relevant; this repo manages NixOS hosts only.

## 9. Storage budget

The user's host (`system76`) has 107 GiB free on root. The investigation must show none of the cuts requires more than a small fraction of that for a single-file workflow.

### 9.1 Production parameters (from `secrets/duplicati-config.json`)

| Target                  | `--blocksize`     | `--dblock-size`    | Source path              |
| ----------------------- | ----------------- | ------------------ | ------------------------ |
| `bankdata`              | 1 MiB (override)  | 200 MiB (override) | `/bankData`              |
| `bankdata-jim-woodring` | 100 KiB (default) | 50 MiB (default)   | `/bankData/Jim Woodring` |

Both targets use the same R2 bucket `duplicati-nixos-backups` under prefix `<host>/<slug>/`.

Live archive sizes (queried `aws s3 ls --recursive --summarize` against R2):

| Target                  | dblock count |                dblock total | dblock avg | dindex count | dindex total | dlist (snapshots) | dlist total |
| ----------------------- | -----------: | --------------------------: | ---------: | -----------: | -----------: | ----------------: | ----------: |
| `bankdata`              |       55,680 | 2,735,779.6 MiB (~2.67 TiB) |  49.13 MiB |       55,683 |   323.90 MiB |                 2 |   48.60 MiB |
| `bankdata-jim-woodring` |            2 |                   62.50 MiB |  31.25 MiB |            2 |     0.01 MiB |                 1 |    0.01 MiB |

Two observations from the live numbers:

- The `bankdata` average dblock is ~49 MiB, well below the configured 200 MiB cap. The override (`--dblock-size=200MB`) only governs new dblock creation; the bulk of the archive predates the override and was written under the 50 MiB default. New writes will tend toward the 200 MiB cap as the archive grows.
- `bankdata` is 2.67 TiB encrypted. A full local restore is impossible on the 107 GiB free root volume and would still exceed any reasonably sized scratch volume on this host. Browsing or single-file extraction is the only viable interactive workflow against this archive; this is the constraint that drives the "build Cut A and Cut B" recommendation rather than waiting for FUSE.

### 9.2 Storage cost model

For one read of a file of plaintext size `F`, backed by `N = ceil(F / blocksize)` content blocks plus optional blocklist blocks:

```
peak_local_disk =
    F                    # plaintext output (only if writing to a file; FUSE read() never persists)
  + cache_cap            # encrypted dblock cache, bounded by config (default 1 GiB)
  + tmp                  # SQLite tempspace + dlist working copy (small; <50 MiB)
```

Encrypted dblocks fetched at runtime: at most `D = min(N, ceil(F / dblock-size))` distinct dblocks, since every block lives in exactly one dblock and dblocks pack contiguous content. With dedup across snapshots, `D` is typically much smaller than the naive ceiling.

Plaintext is **never** written outside the explicit output target. Decryption and zip extraction stream block bytes through process memory only.

### 9.3 Per-cut concrete numbers

| Quantity for one read of file `F` | Cut A (list) | Cut B (extract)                       | Cut C (FUSE read)                     |
| --------------------------------- | ------------ | ------------------------------------- | ------------------------------------- |
| R2 GET bytes                      | 0            | <= F + dlist (one-time, ~25 MiB)      | <= F + dlist (one-time, ~25 MiB)      |
| Persistent local disk written     | 0            | F (output)                            | 0 (read served from memory + cache)   |
| Encrypted-cache disk used         | 0            | <= cache_cap (default 1 GiB, tunable) | <= cache_cap (default 1 GiB, tunable) |
| Process memory peak               | trivial      | one dblock-size (200 MiB worst case)  | one dblock-size (200 MiB worst case)  |
| Cold start (first ever query)     | trivial      | + 1 dlist download (~25 MiB)          | + 1 dlist download (~25 MiB)          |

`bankdata` worst-case dblock size is 200 MiB; live average is ~49 MiB (mostly pre-override volumes). `bankdata-jim-woodring` is 50 MiB worst case. Either fits in process memory comfortably. The dlist download size is sized from the live archive (`bankdata` has 2 dlists totalling 48.6 MiB encrypted, so the latest is ~25 MiB).

### 9.4 Worked examples

Assume `bankdata` (`blocksize=1 MiB`, configured `dblock-size=200 MiB`, observed average dblock ~49 MiB on existing pre-override volumes).

- **10 MiB file**, fully contained in one dblock: peak fetch = 49..200 MiB encrypted (one dblock); output = 10 MiB; cache holds the single dblock. Total transient = 60..210 MiB.
- **5 GiB file** (5120 blocks of 1 MiB): packs into ~26 dblocks if each is at the 200 MiB cap, or up to ~107 dblocks at the legacy 49 MiB average. Bytes fetched is bounded by the file size itself (~5 GiB encrypted) regardless of dblock count, because the same 5 GiB of plaintext content sits inside 5 GiB of encrypted bytes plus a few percent zip + AES wrapper overhead. With `cache_cap = 1 GiB`, the cache rotates and at any one time holds <= 1 GiB of encrypted dblocks plus the partial output file. Peak disk = 5 GiB output + 1 GiB cache = 6 GiB. Fits with 100+ GiB to spare.
- **50 GiB file**, single archive: 50 GiB output + 1 GiB cache = 51 GiB. Fits.
- **Full archive restore** (theoretical, not the use case): `bankdata` is 2.67 TiB encrypted. The 107 GiB free root cannot hold this and never could; even after subtracting Duplicati's compression and dedup, the plaintext is far above the local capacity. This is the structural reason Cut A and Cut B exist: they are the only practical interface to a multi-TiB archive on this host.

### 9.5 Cache strategy

The cache is an optimisation, never a requirement.

- **No cache (`--cache=0`)**: every block read re-downloads its dblock. Slow, but disk usage is exactly `F` for an extract or zero for a FUSE read. Use this when local disk is critically tight.
- **Default cache (`--cache=1G`)**: rotating LRU. Eliminates redundant fetches inside one file extract or one filesystem walk.
- **Big cache (`--cache=20G`)**: useful when repeatedly browsing the same snapshot; the second pass is essentially free.

Cache lives at `$XDG_CACHE_HOME/duplicati-r2-mount/<host>/<slug>/`, mode 0700. Eviction policy is dblock-granular LRU; a partial dblock is never persisted (decrypts must complete before insertion to keep HMAC integrity meaningful).

### 9.6 Side-finding: state-dir ACL was masked to `---` (fixed in this branch)

Pre-fix, the ACL on `/var/lib/duplicati-r2/` looked like this:

```
user:vx:r-x         #effective:---
mask::---
```

The `mask::---` entry nullified the named-user grant. `services.duplicati-r2.stateDirReadableBy` was therefore non-functional: `vx` could not read the SQLite databases despite the configuration. Root cause: the `A+` tmpfiles rules in `modules/services/duplicati-r2.nix` did not include an explicit mask term, so the kernel computed the mask from the empty group-class bits on the 0700 directory and set it to `---`.

The persistent fix is in this branch: each `A+` rule now carries `m::r-x` (and `d:m::r-x` where a default ACL is also seeded), so subsequent activations apply the correct mask. Existing state directories pick up the new mask on the next `nixos-rebuild switch`.

To verify after deploy:

```bash
getfacl /var/lib/duplicati-r2/ | grep -E '^(user|mask)'
# Expect: mask::r-x, and named-user effective r-x (no `#effective:---`).
```

If the deploy ran but a previously-created subdirectory still shows `mask::---`, refresh in place without changing the 0700 mode bits:

```bash
sudo setfacl -m m::r-x /var/lib/duplicati-r2/
sudo setfacl -d -m m::r-x /var/lib/duplicati-r2/
sudo find /var/lib/duplicati-r2 -exec setfacl -m m::r-x {} +
sudo find /var/lib/duplicati-r2 -type d -exec setfacl -d -m m::r-x {} +
```

This was a prerequisite for Cut A, Cut B, and Cut C; all three depend on the ACL working.

### 9.7 Conclusion: storage is not a blocker (and the archive scale makes the cuts mandatory)

- Cut A: zero R2 download, zero plaintext on disk. Works today on 107 GiB free.
- Cut B: per-file fetch ceiling = output file size + cache cap. With default 1 GiB cache, any single file up to ~100 GiB extracts comfortably.
- Cut C: per-`read()` cost = same fetch ceiling, but plaintext stays in memory; persistent disk = cache cap only.

The "limited local storage" constraint is more than satisfied: it is the constraint that promotes Cut A and Cut B from "ergonomics" to "the only available interface". `bankdata` is 2.67 TiB encrypted on R2 (Section 9.1). Pulling the archive in full to inspect or recover a single file is not an option on this host and would not be on any reasonably sized scratch volume either. The decisive factor for deferring Cut C remains the FUSE-semantics maintenance cost and Cut B already covering the common workflow.

## 10. References

### Local

- `docs/duplicati/README.md`
- `docs/duplicati/operations.md`
- `docs/duplicati/recovery.md`
- `docs/duplicati/reference.md`
- `docs/duplicati/security.md`
- `modules/services/duplicati-r2.nix`

### Upstream Duplicati (cited by file + symbol)

- `Duplicati/Library/Main/Database/Database schema/Schema.sql` (current schema, version 19).
- `Duplicati/Library/Main/Database/Database schema/9. Refactor Paths.sql` (path-prefix optimisation).
- `Duplicati/Library/Main/Volumes/VolumeBase.cs:ParseFilename` (filename grammar).
- `Duplicati/Library/Main/Volumes/{BlockVolumeReader,IndexVolumeReader,FilesetVolumeReader}.cs` (zip-entry layout).
- `Tools/Commandline/RestoreFromPython/restore_from_python.py` (Python recovery template).
- `duplicati/sharpaescrypt:src/Constants.cs` (format constants).
- `duplicati/sharpaescrypt:src/SetupHelper.cs` (KDF, AES mode, HMAC mode).

### Upstream Duplicati documentation (`~/git/duplicati-docs`)

- `technical-details/architecture-premises.md`
- `technical-details/understanding-backup/how-backup-works.md`
- `technical-details/understanding-backup/encryption-algorithms.md`
- `technical-details/understanding-backup/backup-size-parameters.md`
- `technical-details/understanding-restore/how-restore-works.md`
- `technical-details/understanding-restore/disaster-recovery.md`
- `technical-details/database-versions.md`
- `detailed-descriptions/database-and-storage/the-local-database.md`
- `duplicati-programs/command-line-interface-cli-1/recoverytool.md`
- `duplicati-programs/command-line-interface-cli-1/sharpaescrypt.md`

### Format and library references

- AES Crypt File Format spec: <https://www.aescrypt.com/aes_stream_format.html>
- Upstream FUSE feature request: <https://github.com/duplicati/duplicati/issues/3081>
- `pyAesCrypt`: <https://github.com/marcobellaccini/pyAesCrypt>
- `aescrypt-rs`: <https://crates.io/crates/aescrypt-rs>
- Comparable mount: `borg mount` <https://borgbackup.readthedocs.io/en/stable/usage/mount.html>; `restic mount` documentation in the restic project.
