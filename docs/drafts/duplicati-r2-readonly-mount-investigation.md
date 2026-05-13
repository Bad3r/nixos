# Duplicati R2 read-only mount investigation

Investigation closing GitHub issue [#204](https://github.com/Bad3r/nixos/issues/204): "investigate(duplicati): read-only mount for encrypted R2 backup archives".

Originally a design decision; Cut A and Cut B are now implemented in this branch, and Cut C is the next implementation step in the same branch/PR. This document is updated in place to record what has shipped so far and the remaining mount-specific work. Recommendation is at the end.

## TL;DR

- **Cut A (shipped)** (path-listing CLI from local SQLite, no decryption): low cost, no crypto dependency, immediate forensic value, reuses `services.duplicati-r2.stateDirReadableBy`.
- **Cut B (implemented in this branch)** (single-file extract by path with on-demand R2 fetch + decrypt): solves the original "read one file without a full restore" problem at a fraction of the implementation cost of FUSE.
- **Cut C (next in this branch/PR)** (read-only FUSE mount): adds the filesystem surface on top of the Cut B resolver, fetcher, decryptor, and cache. The remaining work is the FS-semantics layer: `pyfuse3` packaging, Linux-only service wiring, foreground mount lifecycle, `getattr`/`readdir`/`open`/`read`/`release`, partial-range reads, mount hardening, and explicit FUSE `allow_other` gating.
- **Reject** any approach that re-derives metadata from R2 instead of reusing the per-target SQLite databases. Recreate-from-remote is heavy (`repair` against a missing DB downloads every dindex) and the local DB is already exposed by the `stateDirReadableBy` ACL.

**Local-storage budget**: none of the three cuts requires downloading the full archive. Cut A is zero-byte-ingress (reads only the local SQLite that already exists on disk). Cut B and Cut C download exactly the dblocks needed to satisfy the active read; the encrypted-dblock cache is bounded and configurable (default 1 GiB). See [Section 9](#9-storage-budget).

## Investigation scope

The investigation answers six questions from issue #204:

1. Is there prior art that already decrypts the dblock format outside `duplicati-cli`?
2. What is the precise on-the-wire format (encryption wrapper, dindex, dlist, dblock)?
3. Which SQLite tables resolve `(path, snapshot)` to `(volume, offset, length)`, and is `mode=ro&immutable=1` against the live state directory safe?
4. What does the end-to-end design look like (credentials, fetcher, decrypt, zip, FUSE, lifecycle)?
5. What is the smallest useful cut?
6. What are the build/sequence/reject criteria?

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
- External dependencies: [`pycryptodome`](https://www.pycryptodome.org/) (`Crypto.Cipher.AES`, `Crypto.Hash.SHA256`, `Crypto.Hash.HMAC`); the rest is stdlib (`zipfile`, `sqlite3`, `hashlib`, `base64`, `argparse`). Vendored alongside the script: `pyaescrypt.py` (a header-stamped 2016 copy of [pyAesCrypt 0.1.2](https://github.com/marcobellaccini/pyAesCrypt) by Marco Bellaccini) and `ijson.py`. Cut B can either reuse the vendored bundle or substitute the maintained PyPI [`pyAesCrypt 6.x`](https://pypi.org/project/pyAesCrypt/) package.
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

| Language | Library                                                                                                                   | Format versions | Maintained                    |
| -------- | ------------------------------------------------------------------------------------------------------------------------- | --------------- | ----------------------------- |
| Python   | [`pyAesCrypt`](https://github.com/marcobellaccini/pyAesCrypt) (vendored 0.1.2 in `RestoreFromPython`; PyPI 6.x available) | v2 only         | Last release 6.1.1 (Nov 2023) |
| Rust     | [`aescrypt-rs`](https://crates.io/crates/aescrypt-rs)                                                                     | v0..v3          | Actively maintained           |
| Go       | [`andreacioni/aescrypt`](https://pkg.go.dev/github.com/andreacioni/aescrypt)                                              | v1, v2          | Light-touch                   |
| Dart     | [`alexgoussev/aes_crypt`](https://github.com/alexgoussev/aes_crypt)                                                       | v2              | Active                        |

`pyAesCrypt` covers the format produced by Duplicati today (v2 default). Duplicati 2.3.0.101 added optional v3 output behind `DUPLICATI__AES_VERSION=3`; if v3 is ever turned on, switching to `aescrypt-rs` (or contributing v3 support to `pyAesCrypt`) is the migration path.

### 1.5 Comparable tools in adjacent backup ecosystems

- **Borg**: ships `borg mount` natively (FUSE).
- **Restic**: `restic mount` is in stable releases.
- **Duplicacy**: still requesting FUSE ([gilbertchen/duplicacy#7](https://github.com/gilbertchen/duplicacy/issues/7)).
- **rclone mount**: cross-platform via WinFsp; not relevant because rclone has no Duplicati-format awareness, so mounting the bucket exposes the raw `*.dblock.zip.aes` ciphertext objects rather than the snapshot tree.

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
  "Created": "20260509T120000Z",
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
  AND rv.State IN ('Verified', 'Uploaded')  -- excludes Temporary, Uploading, Deleting, Deleted per Duplicati.Library.Main.Enums.cs:RemoteVolumeState (six-member enum: Temporary, Uploading, Uploaded, Verified, Deleting, Deleted); these two are the states that name a remote object the local database expects to be present, but an `Uploaded`-without-`Verified` row can still 404 on R2 (see §5.2 on multipart-orphaned dblocks)
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

The `GLOB` pattern shown above is convenient but does not generally hit the `FileLookupPath` index, because `File.Path` is the concatenation `PathPrefix.Prefix || FileLookup.Path` exposed by the `File` view and SQLite cannot push a GLOB on a concatenated column down to either underlying index. A production reader should instead resolve `:parent` to a `PathPrefix.ID` (or pair of IDs spanning the prefix) and query `FileLookup` directly with `PrefixID = ?`, then re-join `PathPrefix` only for the final display string. Schema migration "9. Refactor Paths.sql" introduced this prefix split; the lookup speedup is unlocked by querying `FileLookup`, not by the `File` view.

### 3.5 Read-only opener safety

The `services.duplicati-r2.stateDirReadableBy` ACL appends three POSIX ACL rules (in `modules/services/duplicati-r2.nix`, `systemd.tmpfiles.rules` block):

```
A+ <stateDir>      - - - - u:<user>:rX,m::r-x,d:u:<user>:rX,d:m::r-x
A+ <stateDir>/*    - - - - u:<user>:rX,m::r-x,d:u:<user>:rX,d:m::r-x
A+ <stateDir>/*/*  - - - - u:<user>:rX,m::r-x
```

The maintainer gets read access to the SQLite file and to the WAL/SHM sidecar files `duplicati-cli` may create alongside it. The default ACL propagates `u:<user>:rX` to descendants; the kernel's create-mode mask filter would otherwise collapse the inherited mask to `---` on every newly-created mode-0600 file, so the explicit `m::r-x` and the backup script's post-run `setfacl -R -m m::r-x` keep the named-user grant effective (see §9.6).

**What was actually shipped**: Cut A and Cut B both open the database with `file:<percent-encoded path>?mode=ro` and apply `PRAGMA query_only = ON;` after open. `immutable=1` is deliberately not set. The reason is that Duplicati continues to write to the live database between operator queries, and `immutable=1` would make SQLite ignore WAL replay and return stale or torn rows. The trade-off:

- `mode=ro` lets SQLite acquire shared locks and replay the WAL, so the reader sees the last durably-committed transaction (including WAL-resident changes).
- The shared-lock acquisition needs write on the WAL/SHM sidecar files, which `stateDirReadableBy` grants via the per-target depth-2 ACL. Cut A's installCheckPhase confirms reads work concurrently against a writer.
- `mode=ro` cannot corrupt the database (the engine refuses writes), and `PRAGMA query_only = ON` doubles up the guarantee at the connection level.

`immutable=1` would still be the right choice for a pure forensic mode where the DB is known to be frozen (e.g., copied off the host for analysis); the tools accept `--db <path>` to point at such a snapshot, and a future operator-mode flag could opt into `immutable=1` if desired. The default targets the common case: querying live state alongside an active duplicati instance.

## 4. End-to-end design

```
+-------------------------------------------------------------------+
|             duplicati-r2-extract  (Cut B, this branch)            |
+-------------------------------------------------------------------+
|                                                                   |
|  +---------------+   read-only   +---------------------------+    |
|  | Path resolver |---------------|  per-target SQLite DB     |    |
|  | (SQL queries) |   mode=ro     |  /var/lib/duplicati-r2/   |    |
|  +-------+-------+               +---------------------------+    |
|          | (volume_name, hash, size, range)                       |
|          v                                                        |
|  +---------------+    GetObject  +---------------------------+    |
|  | R2 fetcher    |-------------->|  R2 (s3 endpoint)         |    |
|  | (boto3, also  |   credentials |  via /etc/duplicati/r2.env|    |
|  |  file://)     |   from env    +---------------------------+    |
|  +-------+-------+                                                |
|          | encrypted bytes                                        |
|          v                                                        |
|  +---------------+   AES decrypt +---------------------------+    |
|  | Crypto layer  |<------------- |  pyAesCrypt (v2)          |    |
|  +-------+-------+ DUPLICATI_PASSPHRASE                           |
|          | inner zip bytes                                        |
|          v                                                        |
|  +---------------+   on-disk     +---------------------------+    |
|  | dblock cache  |<------------> |  $XDG_CACHE_HOME/         |    |
|  | (LRU)         |               |    duplicati-r2-tools/    |    |
|  +-------+-------+               +---------------------------+    |
|          | block bytes                                            |
|          v                                                        |
|  +-----------------------------+                                  |
|  | Output: stdout / file /     |                                  |
|  |   --output-dir mirror tree  |                                  |
|  +-----------------------------+                                  |
+-------------------------------------------------------------------+
```

### 4.1 Credential sourcing

Reuse `/etc/duplicati/r2.env` (the existing rendered dotenv, base mode 0400 root:root). The env file already carries `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `R2_S3_ENDPOINT_URL`, `R2_REGION`, `R2_BUCKET`, `DUPLICATI_PASSPHRASE`. Cut B reads the env file directly (no `sudo -E`): the same `services.duplicati-r2.stateDirReadableBy` ACL that grants read on the state dir also grants `u:<user>:r--` on this file via a `systemd.tmpfiles` `A+` rule (see §9.6). Operator workflows on this repo's hosts therefore just run `duplicati-r2-extract <slug> ...`. Tests and offline forensics use `--source file:///mirror` plus `--passphrase-env <VAR>`, which skips the env file entirely.

Reasons not to issue a separate read-only Cloudflare key pair:

- The Cut B tool is read-only by design; the credential surface is identical to today's `duplicati-cli` usage.
- Cloudflare R2 supports prefix-scoped credentials natively via the [Temporary Credentials API](https://developers.cloudflare.com/r2/api/s3/temporary-credentials/) (no Worker required): a parent token plus a locally signed JWT carrying `paths.prefixPaths` yields a read-only S3 credential bound to a single bucket and prefix. If a future workflow demands tighter blast-radius isolation, this is the path; it can be added without changing the tool because the credential plumbs into the same S3 endpoint as the parent token.

The marginal benefit of a separate read-only pair is small. Cut B reuses `/etc/duplicati/r2.env` by default; a prefix-scoped Temporary Credential is an optional follow-up, independent of the present decision.

### 4.2 R2 fetcher with on-disk cache

- Cut B uses `boto3` with an explicit `endpoint_url` from `R2_S3_ENDPOINT_URL`. Region defaults to `auto` (R2 convention; the endpoint URL identifies the actual datacenter). The `duplicati-cli` minio-client knobs are not needed for plain `GetObject` calls.
- Encrypted dblocks cache on disk under `$XDG_CACHE_HOME/duplicati-r2-tools/<host>/<slug>/<volume_name>` with mode 0600 (cache root mode 0700). Decrypted bytes never touch disk; decryption streams through `io.BytesIO` on each block read.
- LRU eviction with a configurable cap via `--cache-size` (default 1 GiB; `0` disables caching entirely).
- A `--source file:///path` transport is also supported for offline mirror / forensic workflows and is what the synthetic-fixture test uses.

### 4.3 AES decryption layer

- Cut A: not needed.
- Cut B (implemented): the local nix derivation `packages/duplicati-r2-tools/pyaescrypt.nix` packages PyPI [`pyAesCrypt 6.1.1`](https://pypi.org/project/pyAesCrypt/) (depends on `cryptography`). The extract tool calls `pyAesCrypt.decryptStream` with an `io.BytesIO` sink so plaintext stays in process memory. HMAC mismatch surfaces as a hard `EXIT_DATA_ERR` (65) with the offending volume name in the message; never zero-fills, never silently truncates. When upstream Duplicati flips the AES default from v2 to v3, swap the local derivation to a v3-capable library (`pyAesCrypt 7.x` if/when released, or `aescrypt-rs` via PyO3); the `AesDecrypter` boundary is the only code path that needs to change.
- Cut C (next in this branch/PR): same layer will be reused.

### 4.4 Zip-entry seek

- After AES decryption, the inner bytes are a standard zip archive. Cut B opens it with `zipfile.ZipFile(io.BytesIO(...))` and reads each block via `.open(name).read()`. The first read of any volume parses and validates the `manifest` JSON entry; Cut C can cache central-directory byte ranges to avoid re-parsing on every block read.
- Block-entry names are base64url of the block hash. The implementation in `duplicati_r2_extract.py:base64url_name` does `base64.urlsafe_b64encode(hash_bytes).rstrip(b'=').decode('ascii')`; the rstrip is required because Duplicati omits zip-name padding.

### 4.5 FUSE mount runtime (Cut C only)

- Use `pyfuse3` as the binding. Cut C is Linux-only for this repo; macOS/FreeBSD parity is not a goal.
- `duplicati-r2-mount mount <slug> <mountpoint>` runs in the foreground by default. The NixOS service must run the same foreground process under systemd (`Type=simple`), so systemd owns restart, stop, and logging semantics.
- `duplicati-r2-mount unmount <mountpoint>` performs the unmount operation. If unmounting requires the system helper, the command shells out to the packaged `${pkgs.fuse3}/bin/fusermount3 -u <mountpoint>` rather than requiring sudo.
- `--debug` enables verbose lifecycle diagnostics for startup, open handles, read planning, cache hits/misses, busy unmounts, and stale-mount cleanup. Debug output must redact sensitive values: tokens, API keys, passphrases, env-file values, and signed request material.
- Do not enable FUSE `allow_other` by default. Duplicati restore data is sensitive, and the default mount is visible only to the mounting user. `--allow-other` is an explicit CLI flag that adds the `allow_other` FUSE option only when present.
- With `allow_other` enabled, the filesystem reports deliberate read-only attrs for cross-user access (for example directories 0550 and files 0440 for the configured mount group). `pyfuse3.default_options` includes `default_permissions`, so these attrs are the kernel-enforced access contract.
- One FUSE inode is assigned per `(snapshot_id, file_id)`. Inode 1 is the root; top-level directories are snapshot timestamps in `YYYYMMDDTHHMMSSZ` form.
- Metadata comes from `FilesetEntry.Lastmodified` and `Metadataset.Content`; do not synthesise owner/group from source metadata. The mounter owns private mounts; configured service user/group own managed mounts.
- Plaintext exposure stays bounded by mount permissions and FUSE read responses. The mount may reuse the Cut B encrypted-dblock cache, but it must never write plaintext cache files.

### 4.6 Cut C NixOS/runtime packaging policy

- Add `packages/duplicati-r2-tools/mount.nix` and expose it as `pkgs.duplicati-r2-tools.mount`. The binary name is `duplicati-r2-mount`.
- The mount derivation includes `pyfuse3`, the existing R2/AES dependencies, and `fuse3` for the unmount helper. Mark it Linux-only with package metadata such as `meta.platforms = lib.platforms.linux`; list/extract remain mostly portable Python.
- Add flake output `.#duplicati-r2-mount`.
- Add `pkgs.duplicati-r2-tools.mount` to the default `programs.duplicati-r2-tools.extended.packages` list so enabling the tools installs list, extract, and mount.
- `modules/apps/duplicati-r2-tools.nix` only installs binaries on `PATH`; it must not set host-wide FUSE policy merely because the package is installed.
- `modules/services/duplicati-r2.nix` owns the mount runtime options and host policy. Add `services.duplicati-r2.mount.{enable,user,group,mountPoint,allowOther,debug}`.
- `services.duplicati-r2.mount.allowOther` defaults to `false`. Only when `cfg.mount.enable && cfg.mount.allowOther` should the service module set `programs.fuse.userAllowOther = true;` and pass `--allow-other` to the mount command.
- The service passes `--debug` only when `services.duplicati-r2.mount.debug = true`. Debug mode improves busy-unmount and dead-mount diagnostics, but still redacts credentials and passphrases.
- Add an assertion that `services.duplicati-r2.mount.user` is listed in `services.duplicati-r2.stateDirReadableBy`; the mounting user must already have read ACLs for the SQLite state and env file. Normal mount use should not require sudo.
- Create the mountpoint with `systemd.tmpfiles` using the configured user/group and restrictive mode. The service should stop via `duplicati-r2-mount unmount <mountpoint>` or `fusermount3 -u`, and should avoid leaving stale mountpoints or confusing dead mounts after stop/restart.
- Enable the managed mount service on `system76` only. `tpnix` should not enable it unless that host later grants `stateDirReadableBy` and explicitly opts into the mount runtime.

### 4.7 Cut C validation boundaries

- A Nix build sandbox cannot perform a real FUSE mount here: a sandboxed `runCommand` check for `/dev/fuse` returned `missing`. Therefore `mount.nix` must not require `/dev/fuse` or a real mount during `installCheckPhase`.
- In-package checks should cover import/compile, fake filesystem object tests, `getattr`/`readdir`/`read`/`readlink` behavior over fixture data, and reuse of the existing resolver/decrypt/cache code paths.
- Host or VM validation on `system76` covers the real FUSE path: service foreground startup, `ls`, `stat`, `cat`, `readlink`, `grep`, partial reads, unmount, busy-unmount diagnostics with `--debug`, and recovery from dead/stale mount state.

### 4.8 Per-invocation lifecycle (Cut B)

- `duplicati-r2-extract <slug> <path> --output <dest>`: opens the SQLite DB (`mode=ro`), checks `Configuration.Version` is in the supported set, reads `Configuration.blockhash` / `Configuration.filehash` for the BlockHash and FileHash algorithms, sources `/etc/duplicati/r2.env` (or the file specified by `--env-file`) for credentials and the passphrase, then plans + fetches + decrypts + writes in one pass and exits. No background daemon, no mount, no FUSE.
- The encrypted-dblock cache persists between invocations under `$XDG_CACHE_HOME/duplicati-r2-tools/<host>/<slug>/`. Move that directory aside with `rip` to drop it; subsequent runs re-fetch.
- Cut C lifecycle is the foreground `duplicati-r2-mount mount ...` process plus `duplicati-r2-mount unmount <mountpoint>`, optionally supervised by the NixOS systemd service described above. If `--allow-other` is passed, it must be visible in the CLI invocation and backed by the NixOS `services.duplicati-r2.mount.allowOther` gate.

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

**Build cost**: ~1 day. Pure SQL queries, one Python or Bash script. Test surface is fully offline (use a synthetic SQLite DB seeded by `duplicati-cli backup` against `/tmp`); the shipped install check also covers literal directory prefixes containing SQLite `GLOB` metacharacters.

**Risk**: zero crypto risk; no R2 dependency; tool is useless on a host with no local DB (acceptable, mirrors `duplicati-cli` behaviour).

**Value**: solves a meaningful chunk of the original problem: "which file was where in which snapshot at what time" is answerable instantly without paying egress.

### 5.2 Cut B: single-file extract CLI (decrypts on demand)

**Status**: implemented in this branch as `pkgs.duplicati-r2-tools.extract` (binary `duplicati-r2-extract`). Operator workflow: [`../duplicati/operations.md`](../duplicati/operations.md#extract-a-single-file-from-r2-cut-b).

**Scope**: extract one file (or a glob) from a chosen snapshot to stdout, a path, or `-`. Downloads only the dblocks needed.

**Interface as shipped**:

```
duplicati-r2-extract <slug> <path> [--snapshot <id|timestamp>] --output <dest|->
duplicati-r2-extract <slug> --include '<glob>' --output-dir <dest> [--snapshot ...]
duplicati-r2-extract <slug> ... --source file:///mirror   # offline/forensic mode
duplicati-r2-extract <slug> ... --json                    # JSON summary on stderr
```

`--diff` is intentionally not implemented; the same effect is two `--output` extracts piped through `diff(1)`.

**Build cost (actual)**: ~1 day. Reuses Cut A's resolver via `duplicati_r2_common.py`. Adds R2 fetcher (boto3) plus a `--source file://` fallback transport, AES decrypt (`pyAesCrypt`), zip seek, blocklist resolution, LRU on-disk cache. The `installCheckPhase` builds a synthetic Duplicati archive (4 files at 50 B / 4 KiB / 32 KiB / 200 KiB exercising single-block, multi-block-without-blocklist, single-blocklist, and multi-blocklist paths) via `scripts/make_fixture.py` and round-trips every file plus exercises HMAC corruption, missing path, wrong passphrase, glob mode, stdout mode, JSON summary, cache recovery, symlink-safe partial handling, invalid DB hash handling, volume-manifest validation, segment-aware streaming path-qualified include globs, and SQLite variable-limit batching.

**Risk**:

- Upstream format drift on AES v2 -> v3 default (currently opt-in). Mitigation: swap the local `pyaescrypt.nix` derivation when needed; the `AesDecrypter` is the only consumer.
- Blocksize/BlockHash mismatch between the local DB and a re-imported archive. The shipped tool reads `Configuration.blocksize`, `Configuration.blockhash`, and `Configuration.filehash`; each decrypted dblock manifest is checked against those values before any block bytes are trusted.
- Multipart-orphaned dblocks (`Remotevolume.State='Uploaded'` without `'Verified'`) will resolve to 404 on R2. The shipped tool surfaces this at fetch time as `EXIT_OPEN_ERR` (66) with the volume name in the error message; an upfront filter on `Remotevolume.State` is a possible follow-up but would also need to handle the state being `Uploaded` legitimately mid-cycle.

**Value**: solves the original problem stated in #204. Most of the operational use case (browse, grep, single-file recovery) is covered without writing a kernel filesystem.

### 5.3 Cut C: read-only FUSE mount

**Scope**: mount the archive at a path; standard `ls`, `cat`, `grep`, `diff` work transparently against a read-only snapshot tree.

**Implementation sequence**:

- Extract a mount package as `pkgs.duplicati-r2-tools.mount` with binary `duplicati-r2-mount`, using `pyfuse3` and Linux-only metadata (`meta.platforms = lib.platforms.linux`).
- Reuse the Cut B resolver, R2/file source abstraction, AES decryptor, per-block verifier, and encrypted-dblock cache. Do not add a plaintext cache.
- Implement `duplicati-r2-mount mount <slug> <mountpoint>` as a foreground process by default. The NixOS systemd service runs this same foreground process.
- Implement `duplicati-r2-mount unmount <mountpoint>` and shell out to `${pkgs.fuse3}/bin/fusermount3 -u <mountpoint>` when that is the required unmount primitive.
- Implement `--debug` for lifecycle/read/cache/unmount diagnostics, with mandatory redaction for tokens, API keys, passphrases, env-file values, and signed request material.
- Implement `--allow-other` as a CLI opt-in. The NixOS service passes it only when `services.duplicati-r2.mount.allowOther = true`, and that same option is the only path that sets `programs.fuse.userAllowOther = true;`.
- Add `services.duplicati-r2.mount.{enable,user,group,mountPoint,allowOther,debug}` and a `systemd` service in `modules/services/duplicati-r2.nix`. Assert the mount user is included in `stateDirReadableBy`, create the mountpoint via `systemd.tmpfiles`, and keep sudo out of normal operation by using the existing SQLite/env-file ACLs.
- Add `pkgs.duplicati-r2-tools.mount` to the app module's default package list and expose flake output `.#duplicati-r2-mount`.
- Enable the managed mount service from `modules/system76/duplicati.nix` only; `tpnix` should remain off unless it later gets matching state/env-file ACL access and explicitly opts in.

**FUSE semantics work**:

- `getattr`, `readdir`, `open`, `read`, `release`, and `readlink` for symlinks.
- Range reads (`read(offset, len)` mid-block) require partial decompression of one zip entry plus a streaming concatenation across multiple blocks.
- Caching policy decisions: per-block (small, granular) vs per-dblock (large, simple) vs hybrid.
- Race conditions between `release` and active `read` calls.
- Symlink loops, hard-link representation, special files.
- `getxattr`/`listxattr` if the metadata blob is to be exposed.
- Stale/dead mount handling: foreground process ownership, explicit unmount, systemd stop behavior, and debug diagnostics for busy mounts.

**Test plan**:

- In `installCheckPhase`: import/compile, fake filesystem object tests, `getattr`/`readdir`/`read`/`readlink` fixture tests, and resolver/decrypt/cache reuse tests. Do not perform a real FUSE mount in the Nix build sandbox because `/dev/fuse` is absent there.
- On `system76`: service startup, foreground logging, `ls`, `stat`, `cat`, `readlink`, `grep`, partial reads, clean unmount, busy-unmount diagnostics under `--debug`, and restart after a stale/dead mount.

**Risk**: FUSE-on-Linux is stable and acceptable for this repo, but the mount can fail inside kernel callbacks under load rather than at command startup. Cross-user exposure through `allow_other` is security-sensitive and must remain behind the two explicit gates above.

**Value**: matches the Borg/Restic experience. For a single-host repo with two backup targets, the marginal value over Cut B is small.

## 6. Decision criteria

| Criterion              | Weight | Cut A (shipped)                  | Cut B (shipped)                                  | Cut C (next)                                          |
| ---------------------- | ------ | -------------------------------- | ------------------------------------------------ | ----------------------------------------------------- |
| Build cost (actual)    | high   | ~1 day                           | ~1 day on top of Cut A                           | est. 7..14 days additional                            |
| Format-drift risk      | high   | nil (no crypto/zip)              | low (AES v2->v3 only)                            | medium (zip + FS)                                     |
| Maintenance over years | high   | trivial                          | small                                            | recurring                                             |
| Crypto risk            | high   | nil                              | low (PyPI pyAesCrypt 6.1.1, HMAC-verified)       | low (same as B)                                       |
| Operator value         | high   | medium (browse/grep)             | high (recover one file or glob)                  | high (browse/cat transparently)                       |
| Packaging              | med    | Python + Nix (stdenvNoCC)        | Python + Nix (stdenvNoCC + python3.withPackages) | Python + `pyfuse3` + Nix; Linux-only                  |
| ACL interaction        | med    | uses `stateDirReadableBy` only   | extends `stateDirReadableBy` to env-file read    | uses state/env-file ACLs; explicit `allow_other` gate |
| Bus-factor protection  | med    | high (works without crypto code) | high (synthetic-fixture test gates regressions)  | medium (FUSE expertise needed)                        |

Hard constraints from issue #204 carried through:

- Read-only against R2 and the local SQLite. Cut A and Cut B respect this trivially; Cut C respects it through FUSE flags.
- No passphrase rotation. None of the cuts modify state.
- No silent zero-fill on corruption. Each cut surfaces errors via stderr/`EIO`.
- Reuse `services.duplicati-r2.stateDir`. All three cuts open the per-target SQLite via the existing ACL.

## 7. Recommendation

**Cut A is shipped** as `pkgs.duplicati-r2-tools.list`. Single-file Python implementation, no R2 access, no AES code. Auto-installed on every host where `services.duplicati-r2.stateDirReadableBy` is non-empty.

**Cut B is implemented in this branch** as `pkgs.duplicati-r2-tools.extract`. Reuses Cut A's resolver via the shared `duplicati_r2_common.py` module. Adds a local `pyAesCrypt` derivation, `boto3` for the R2 transport, an `EncryptedCache` LRU on disk, a `BlockResolver` that handles both `BlocksetEntry`-backed and `BlocklistHash`-chain-backed files, and pluggable `S3Source`/`FileSource` transports (the latter enables offline/mirror operation and underpins the synthetic-fixture test). The `installCheckPhase` exercises single-block, multi-block-without-blocklist, single-blocklist, and multi-blocklist code paths plus HMAC-corruption, missing-path, wrong-passphrase, include-glob, env-file, cache, invalid DB hash, manifest-validation, segment-aware streaming path globbing, and SQLite variable-limit contracts. The env-file ACL was widened in the same change so users in `stateDirReadableBy` can read `/etc/duplicati/r2.env` without sudo; the CLI opens that env file with `O_NOFOLLOW` and validates mode/owner via `fstat` on the opened descriptor.

**Cut C is next in this same branch/PR**. It should reuse the Cut B resolver, R2/file source abstraction, AES decryption boundary, block verifier, and encrypted-dblock cache, then add the read-only `pyfuse3` surface on top. The key implementation risk is not backup-format parsing anymore; it is mount correctness under filesystem access patterns: lifecycle, stale handles, symlink/readlink behavior, partial reads, cache eviction, safe unmount recovery, and keeping cross-user mount exposure behind an explicit `allow_other` opt-in.

Cut C's implementation should keep FUSE permissions private by default. Add `duplicati-r2-mount mount` as a foreground process, `duplicati-r2-mount unmount` backed by `fusermount3 -u`, and a `--debug` mode that improves diagnostics without leaking credentials. Add a CLI `--allow-other` flag, but only have the NixOS service path pass that flag when `services.duplicati-r2.mount.allowOther = true`. The same service option is the only place that should set `programs.fuse.userAllowOther = true;`; package installation and `programs.duplicati-r2-tools.extended.enable` must not change global FUSE policy.

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
  + tmp                  # SQLite tempspace and atomic-write sidecars (small)
```

Encrypted dblocks fetched at runtime: the unique `Remotevolume.Name` set resolved by the `Block.VolumeID -> Remotevolume.ID` join. Current Cut B fetches whole encrypted dblock objects; it does not issue HTTP range reads inside a dblock. For a newly written, mostly contiguous file, the practical estimate is `ceil(F / dblock-size)` dblocks. For highly deduplicated or fragmented files, the upper bound is one dblock per content block, and the exact count is the SQL-derived unique-volume set that `duplicati-r2-extract --json` reports as `dblocks_touched`.

Plaintext is **never** written outside the explicit output target. Decryption and zip extraction stream block bytes through process memory only.

### 9.3 Per-cut concrete numbers

| Quantity for one read of file `F` | Cut A (list) | Cut B (extract)                                              | Cut C (FUSE read)                                          |
| --------------------------------- | ------------ | ------------------------------------------------------------ | ---------------------------------------------------------- |
| R2 GET bytes                      | 0            | whole encrypted dblocks in the SQL-derived unique-volume set | same unless Cut C adds HTTP range reads inside dblocks     |
| Persistent local disk written     | 0            | F (output)                                                   | 0 (read served from memory + cache)                        |
| Encrypted-cache disk used         | 0            | <= cache_cap (default 1 GiB, tunable)                        | <= cache_cap (default 1 GiB, tunable)                      |
| Process memory peak               | trivial      | one dblock-size (200 MiB worst case)                         | one dblock-size (200 MiB worst case)                       |
| Cold start (first ever query)     | trivial      | no dlist GET; local SQLite is the planner                    | no dlist GET if Cut C reuses the same local-SQLite planner |

`bankdata` worst-case dblock size is 200 MiB; live average is ~49 MiB (mostly pre-override volumes). `bankdata-jim-woodring` is 50 MiB worst case. Either fits in process memory comfortably. Neither Cut A nor the shipped Cut B fetches dlist objects from R2 because both plan reads from the local SQLite database.

### 9.4 Worked examples

Assume `bankdata` (`blocksize=1 MiB`, configured `dblock-size=200 MiB`, observed average dblock ~49 MiB on existing pre-override volumes).

- **10 MiB file**, fully contained in one dblock: peak fetch = 49..200 MiB encrypted (one dblock); output = 10 MiB; cache holds the single dblock. Total transient = 60..210 MiB.
- **5 GiB file** (5120 blocks of 1 MiB): packs into ~26 dblocks if each is at the 200 MiB cap, or up to ~105 dblocks at the legacy 49 MiB average. For a contiguous file, bytes fetched are roughly the encrypted dblocks containing those 5 GiB of plaintext plus zip/AES overhead; fragmented or heavily deduplicated files can touch more volumes, and the exact number is the SQL-derived unique-volume set. With `cache_cap = 1 GiB`, the cache rotates and at any one time holds <= 1 GiB of encrypted dblocks plus the partial output file. Peak disk = 5 GiB output + 1 GiB cache = 6 GiB. Fits with 100+ GiB to spare.
- **50 GiB file**, single archive: 50 GiB output + 1 GiB cache = 51 GiB. Fits.
- **Full archive restore** (theoretical, not the use case): `bankdata` is 2.67 TiB encrypted. The 107 GiB free root cannot hold this and never could; even after subtracting Duplicati's compression and dedup, the plaintext is far above the local capacity. This is the structural reason Cut A and Cut B exist: they are the only practical interface to a multi-TiB archive on this host.

### 9.5 Cache strategy

The cache is an optimisation, never a requirement.

- **No cache (`--cache-size 0`)**: every block read re-downloads its dblock. Slow, but disk usage is exactly `F` for an extract or zero for a FUSE read. Use this when local disk is critically tight.
- **Default cache (`--cache-size 1G`)**: rotating LRU. Eliminates redundant fetches inside one file extract.
- **Big cache (`--cache-size 20G`)**: useful when repeatedly extracting different files from the same snapshot; the second pass is essentially free.

Cache lives at `$XDG_CACHE_HOME/duplicati-r2-tools/<host>/<slug>/`, mode 0700. Eviction policy is dblock-granular LRU; a partial dblock is never persisted (the encrypted bytes are only stored after a successful read, and the decrypter runs after the bytes are read back from cache).

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
- Cut B: local disk ceiling = output file size + encrypted cache cap; R2 fetches are the whole dblocks in the SQL-derived unique-volume set. With default 1 GiB cache, any single file up to ~100 GiB extracts comfortably as long as the chosen output path has room for the plaintext.
- Cut C: local disk ceiling remains the encrypted cache cap only; R2 fetch behavior starts the same as Cut B unless the mount implementation adds HTTP range reads inside dblocks.

The "limited local storage" constraint is more than satisfied: it is the constraint that promotes Cut A and Cut B from "ergonomics" to "the only available interface". `bankdata` is 2.67 TiB encrypted on R2 (Section 9.1). Pulling the archive in full to inspect or recover a single file is not an option on this host and would not be on any reasonably sized scratch volume either. Cut C keeps the same storage ceiling and is sequenced after Cut B because the remaining work is FUSE-semantics correctness rather than backup-format discovery.

### 9.8 Live validation against `duplicati-cli restore` (May 2026)

A 44-path `*.torrent` restore from `bankdata` (~10 MiB plaintext) was performed in May 2026 to validate the read-amplification math against real artifacts. Findings:

- The fetch list resolved to 8 unique dblocks (~400 MiB encrypted), matching the `(unique dblocks touched) * dblock_size` figure derived from the §3 SQL: every torrent file's content blocks lived inside one of those 8 dblocks. This is the same `Block.VolumeID -> Remotevolume` join Cut A and Cut B will use.
- The run executed fully in-memory: `find /tmp /var/tmp -name '*.dblock.zip*'` returned nothing during the restore, confirming `duplicati-cli` does not stage encrypted dblocks to disk under default `--restore-volume-cache-hint`. This validates §4's design assumption that the future tools' on-disk cache is an optimisation, not a requirement.
- Default `duplicati-cli restore` concurrency was the dominant bottleneck. Six downloaders / six decryptors / six decompressors / channel buffer 12 produced a single TCP connection to R2 and ~130 KiB/s sustained throughput, putting the ~425 MiB fetch on a 30-minute path. Setting `--restore-volume-downloaders=8`, `--restore-volume-decryptors=8`, `--restore-volume-decompressors=8`, and `--restore-channel-buffer-size=32` is needed to saturate R2's per-bucket concurrent-request envelope. Full recipe: [`../duplicati/operations.md`](../duplicati/operations.md#concurrency-tuning-for-r2).
- `duplicati-cli restore` reads each dblock as a single object: it does not issue HTTP range requests into the inner zip to fetch only the needed entries. The shipped Cut B implementation follows the same whole-dblock fetch model, but narrows the workflow to one file or a glob set, keeps encrypted cache usage bounded, and never stages plaintext outside the chosen sink. HTTP range reads remain a possible Cut C or later Cut B optimisation, not a property of the current implementation.

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
- `pyfuse3`: <https://github.com/libfuse/pyfuse3>
- Comparable mount: `borg mount` <https://borgbackup.readthedocs.io/en/stable/usage/mount.html>; `restic mount` documentation in the restic project.
