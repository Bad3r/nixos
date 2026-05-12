# Duplicati R2 Operations

Runbooks for everyday changes: provisioning secrets, editing the manifest, manual backup and restore, post-deploy validation. Every step is non-interactive and safe to script. Commands assume `cwd = /home/<owner>/nixos` (or any clone root) and the dev shell from `nix develop`.

## Provision secrets

### Credentials

`secrets/duplicati-r2.yaml` carries the R2 access pair, optional jurisdiction endpoint, and the duplicati passphrase. Encrypt in place after editing:

```bash
nix develop -c sops -e -i secrets/duplicati-r2.yaml
```

Required keys map to environment variables. The default selectors are `duplicati-r2/<NAME>`. If the encrypted file uses different keys, override them in the host module under `services.duplicati-r2.credentials.<NAME>.secret`.

```yaml
duplicati-r2:
  AWS_ACCESS_KEY_ID: <ACCESS_KEY_ID>
  AWS_SECRET_ACCESS_KEY: <SECRET_ACCESS_KEY>
  R2_ACCOUNT_ID: <ACCOUNT_ID>
  R2_API_TOKEN: <API_TOKEN>
  R2_BUCKET: <bucket>
  R2_S3_ENDPOINT: <ACCOUNT_ID>.<region>.r2.cloudflarestorage.com
  R2_S3_ENDPOINT_URL: https://<ACCOUNT_ID>.<region>.r2.cloudflarestorage.com
  R2_REGION: <region>
  DUPLICATI_PASSPHRASE: <passphrase>
```

Note: the duplicati passphrase is fixed for the lifetime of every existing archive. Only set it once; rotating it abandons all prior backups (see [security.md](security.md)).

### Manifest

The manifest is stored as a SOPS binary-mode file. The decrypted form is the JSON payload itself; SOPS wraps the ciphertext under a top-level `data` key in the encrypted file, and binary-mode decryption strips that wrapper. To create or replace the manifest from scratch, write plaintext JSON to a temporary file and encrypt with `--filename-override` so the `.sops.yaml` rule for `secrets/*.json` selects the correct age recipient:

```bash
cat > /tmp/manifest.json <<'JSON'
{
  "environmentFile": "/etc/duplicati/r2.env",
  "bucket": "<bucket>",
  "targets": {
    "photos": {
      "path": "/srv/photos",
      "onCalendar": "daily",
      "extraArgs": ["--throttle-upload=5MB"]
    }
  },
  "verify": { "onCalendar": "weekly", "samples": 50 }
}
JSON

sops -e --input-type binary --output-type binary \
  --filename-override secrets/duplicati-config.json \
  /tmp/manifest.json > secrets/duplicati-config.json
rm /tmp/manifest.json
```

Inspect the active manifest:

```bash
sops -d --input-type binary --output-type binary secrets/duplicati-config.json | jq
```

## Wire the module in a host

Each host module (`modules/<host>/duplicati.nix`) takes `metaOwner` and `secretsRoot` from `_module.args` and gates on the presence of both encrypted files:

```nix
{
  lib,
  metaOwner,
  secretsRoot,
  ...
}:
let
  manifestFile = "${secretsRoot}/duplicati-config.json";
  credentialsFile = "${secretsRoot}/duplicati-r2.yaml";
  ready = (builtins.pathExists manifestFile) && (builtins.pathExists credentialsFile);
in
{
  configurations.nixos.<host>.module = _: {
    config = lib.mkMerge [
      (lib.mkIf ready {
        services.duplicati-r2 = {
          enable = true;
          configFile = manifestFile;
          stateDirReadableBy = [ metaOwner.username ];
        };
      })
      (lib.mkIf (!ready) {
        warnings = [
          "services.duplicati-r2 is disabled because secrets are missing."
        ];
      })
    ];
  };
}
```

Import the module in the host closure (typically `modules/<host>/imports.nix`) via `config.flake.nixosModules."duplicati-r2"`. Order it after `sops-nix`'s module so the secret declarations are valid.

## Add a target

```bash
tmp=$(mktemp -d)
sops -d --input-type binary --output-type binary \
  secrets/duplicati-config.json > "$tmp/manifest.json"

jq '.targets["<slug>"] = {
      enable: true,
      path: "/abs/path",
      onCalendar: "daily",
      retention: "30D:1D",
      extraArgs: []
    }' "$tmp/manifest.json" > "$tmp/manifest.new.json"

sops -e --input-type binary --output-type binary \
  --filename-override secrets/duplicati-config.json \
  "$tmp/manifest.new.json" > secrets/duplicati-config.json
rm -rf "$tmp"
```

Validate the schedule before committing the change:

```bash
nix develop -c scripts/validate-oncalendar.sh 'daily'
```

Commit the encrypted file, then deploy. The activation flow restarts `duplicati-r2-generate-units.service`, which writes the new units and starts their timers immediately.

## Edit a target

Same flow as add. Common edits:

```bash
# Change the schedule
jq '.targets["<slug>"].onCalendar = "Mon..Fri 02:00:00"' ...

# Change the source path
jq '.targets["<slug>"].path = "/new/abs/path"' ...

# Append an extra arg
jq '.targets["<slug>"].extraArgs += ["--throttle-upload=10MB"]' ...

# Drop retention (keep all versions)
jq 'del(.targets["<slug>"].retention)' ...
```

## Disable a target

`enable: false` is the supported reversible mechanism. The generator removes the corresponding backup and verify units on the next activation; remote data is untouched and the manifest entry remains for re-enablement later.

```bash
tmp=$(mktemp -d)
sops -d --input-type binary --output-type binary \
  secrets/duplicati-config.json > "$tmp/manifest.json"
jq '.targets["<slug>"].enable = false' "$tmp/manifest.json" > "$tmp/manifest.new.json"
sops -e --input-type binary --output-type binary \
  --filename-override secrets/duplicati-config.json \
  "$tmp/manifest.new.json" > secrets/duplicati-config.json
rm -rf "$tmp"
```

To re-enable, set `enable: true` (or `del(.targets[<slug>].enable)`, since omitted means `true`) and redeploy.

## Manual operations

```bash
# Run a backup now
sudo systemctl start duplicati-r2-backup-<slug>.service

# Tail the journal for the last invocation
journalctl -xeu duplicati-r2-backup-<slug>.service

# Force verification
sudo systemctl start duplicati-r2-verify-<slug>.service

# List currently registered timers
systemctl list-timers 'duplicati-r2-backup-*' 'duplicati-r2-verify-*'

# Inspect the runtime manifest
sudo jq . /run/duplicati-r2/config.json
```

`duplicati-cli` resolves credentials from `/etc/duplicati/r2.env`, which is mode 0400 root:root. Direct invocation of `duplicati-cli` therefore needs root or the env passed in explicitly.

## Restore

To restore a target into `/tmp/restore`:

```bash
sudo bash <<'RESTORE'
set -euo pipefail
umask 077

set -a
. /etc/duplicati/r2.env
set +a

# duplicati's S3 backend reads credentials from AUTH_USERNAME / AUTH_PASSWORD.
# Without these, the operation fails with `S3NoAmzUserID: No S3 userID given`.
export AUTH_USERNAME="$AWS_ACCESS_KEY_ID"
export AUTH_PASSWORD="$AWS_SECRET_ACCESS_KEY"

dest="s3://${R2_BUCKET}/$(hostname --short)/<slug>?use-ssl=true&s3-ext-disablehostprefixinjection=true&s3-disable-chunk-encoding=true&s3-client=minio&s3-server-name=${R2_S3_ENDPOINT}"

duplicati-cli restore "$dest" \
  --restore-path=/tmp/restore \
  --passphrase="$DUPLICATI_PASSPHRASE" \
  --restore-volume-downloaders=8 \
  --restore-volume-decryptors=8 \
  --restore-volume-decompressors=8 \
  --restore-channel-buffer-size=32
RESTORE
```

Adjust with `--version`, `--time`, or `--include` filters as needed. Wipe `/tmp/restore` once finished.

### Concurrency tuning for R2

Out-of-the-box defaults for `duplicati-cli restore` (six downloaders, six decryptors, six decompressors, channel buffer size twelve) under-perform against Cloudflare R2. A single-file restore from `bankdata` recovering 44 `*.torrent` paths (~10 MiB plaintext, fetch ceiling ~425 MiB across 8 dblocks) was observed at ~130 KiB/s through a single TCP connection to R2; every worker thread sat idle at 0% CPU, with the run on track for a ~30 minute completion. The four flags below keep the pipeline saturated when individual TCP streams to R2 are slow:

| Option                           | Default | Recommended | Effect                                                                   |
| -------------------------------- | ------- | ----------- | ------------------------------------------------------------------------ |
| `--restore-volume-downloaders`   | 6       | 8           | Concurrent dblock fetches over distinct TCP connections.                 |
| `--restore-volume-decryptors`    | 6       | 8           | Threads running the AES Crypt decrypt loop in parallel.                  |
| `--restore-volume-decompressors` | 6       | 8           | Threads unzipping the inner dblock zip in parallel.                      |
| `--restore-channel-buffer-size`  | 12      | 32          | Inter-stage queue depth between download / decrypt / decompress / write. |

Two checks are useful: (1) confirm the pipeline is actually moving bytes, (2) measure achieved throughput. Connection count is a weaker signal because the AWS SDK / minio client may pool requests over a small number of long-lived TCP connections regardless of pipeline depth.

Resolve the duplicati pid by process name (the kernel `comm` is `Duplicati.Comma`, truncated from `Duplicati.CommandLine`); avoid `pgrep -f` because it matches against the full command line and will catch the shell that invoked `pgrep` itself:

```bash
DUP_PID=$(pgrep -nx Duplicati.Comma)
echo "duplicati pid=$DUP_PID"
```

Throughput sample (the most reliable check; `rchar` counts every byte the process has read, dominated during restore by socket reads). Captures two `rchar` snapshots five seconds apart and prints the rate in KiB/s via `bc`:

```bash
rchar_start=$(sudo awk '/^rchar:/ {print $2}' /proc/$DUP_PID/io)
sleep 5
rchar_end=$(sudo awk '/^rchar:/ {print $2}' /proc/$DUP_PID/io)
echo "scale=1; print ($rchar_end - $rchar_start) / 5 / 1024, \" KiB/s\n\"" | bc
```

Sustained rates below ~1000 KiB/s indicate the concurrency flags are not effective and the queue feeding the downloaders is empty. Rates in the 5,000 to 30,000 KiB/s range are typical of a saturated R2 path.

Optional secondary check, the count of established sockets owned by duplicati:

```bash
sudo ss -tnp state established | grep "pid=$DUP_PID," | wc -l
```

A count of 1 is not by itself a problem; HTTP keep-alive plus AWS-SDK connection pooling can serve many parallel requests over a single TCP socket. Throughput is the authoritative signal.

Pushing past 8/32 rarely helps further; R2 caps per-bucket concurrent requests and the duplicati pipeline becomes channel-buffer-bound past that point.

### Memory vs on-disk cache

duplicati holds each encrypted dblock in process RAM during restore; nothing in the pipeline requires staging dblocks to disk. With the 8-deep pipeline above the steady-state encrypted footprint is approximately `8 * dblock_size`: ~400 MiB on the 50 MiB-average legacy `bankdata` volumes, up to ~1.6 GiB on dblocks written under the current 200 MiB cap. Both fit comfortably in RAM on the hosts in this repo.

`--restore-volume-cache-hint` is unset by default, which selects unlimited mode with disk-aware eviction (`--restore-volume-cache-min-free=1gb`). On a host with ample free RAM and `/tmp` on tmpfs, the cache effectively never spills; checking `/tmp` and `/var/tmp` for `*.dblock.zip*` during a live restore confirms duplicati is running in-memory.

To explicitly bound the in-memory cache, set `--restore-volume-cache-hint=2gb` (or similar). Setting `--restore-volume-cache-hint=0` disables the encrypted-dblock cache entirely and re-downloads on every block read; the default mode is correct for these archive sizes.

### Filtering and read amplification

`--include='*.torrent'` (or any other glob) selects which file paths inside the snapshot are restored. The restore engine still has to fetch the dblocks that contain those files' content blocks: with default deduplication and 50 MiB to 200 MiB dblock packing, the bytes-on-the-wire ceiling is `(unique dblocks touched) * dblock_size`, not the plaintext output size. The example above (44 torrent files, ~10 MiB plaintext, 8 unique dblocks, ~400 MiB encrypted) is a 40x amplification: every dblock that contains at least one matching block must be downloaded in full because `duplicati-cli restore` does not perform HTTP range reads inside the dblock object.

To compute the exact dblock fetch list before running a restore, query the per-target SQLite using the `Path -> Blockset -> Block -> Remotevolume` join from [recovery.md](recovery.md#db-driven-impact-analysis), substituting the path filter (e.g. `Path LIKE '%.torrent'`) for the missing-volume names. The result is the precise set of `*.dblock.zip.aes` objects the restore will fetch.

## Query the local SQLite (read-only)

`duplicati-r2-list` (provided by `pkgs.duplicati-r2-tools.list`) answers snapshot, path, size, mtime, and version-history questions directly from the per-target SQLite at `/var/lib/duplicati-r2/<slug>/duplicati-r2-<slug>.sqlite`. It opens the database with `mode=ro` (the URI path is percent-encoded so spaces or `?`/`#` in the state-dir survive), performs no R2 fetches, and does not decrypt anything. The `immutable=1` flag deliberately is not set: Duplicati keeps writing to the same database, and `immutable=1` would make SQLite ignore WAL replay and return stale or torn rows. Cut A of [`docs/drafts/duplicati-r2-readonly-mount-investigation.md`](../drafts/duplicati-r2-readonly-mount-investigation.md).

The tool is auto-installed on every host where `services.duplicati-r2.stateDirReadableBy` is non-empty; usernames listed there can run it without `sudo` via the named-user POSIX ACL on the state directory. Other users see `permission denied` on the SQLite open, which is the expected loud failure.

Subcommands (replace `<slug>` with the manifest target key, e.g. `bankdata`):

```bash
# List snapshots, newest first (Fileset.ID, ISO timestamp, full-backup flag).
duplicati-r2-list versions <slug>

# Directory listing at a snapshot (defaults to latest).
duplicati-r2-list ls <slug> /abs/path
duplicati-r2-list ls --snapshot 42 <slug> /abs/path
duplicati-r2-list ls --snapshot 2026-04-01T00:00:00Z <slug> /abs/path

# Size, hash, and mtime for a single file in a snapshot.
duplicati-r2-list stat <slug> /abs/path/file.ext

# Every snapshot that contains a path, with per-snapshot size and mtime.
duplicati-r2-list history <slug> /abs/path/file.ext

# Path-glob filter over a snapshot (NOT a content grep). Use --regex for re syntax.
duplicati-r2-list grep <slug> '*.torrent'
duplicati-r2-list grep <slug> --regex '\.torrent$'
```

Global flags:

| Flag              | Effect                                                                                              |
| ----------------- | --------------------------------------------------------------------------------------------------- |
| `--json`          | Stream output as NDJSON (one row per line for streaming subcommands; one object for `stat`).        |
| `--db <path>`     | Bypass manifest resolution and open the named SQLite file directly. Used for offline forensic work. |
| `--config <path>` | Override `/run/duplicati-r2/config.json` for slug-to-stateDir resolution.                           |
| `--snapshot <id>` | (`ls`, `stat`, `grep`) Fileset.ID integer or ISO-8601 timestamp; default is the latest snapshot.    |

Exit codes mirror `duplicati-r2-restore.sh`:

- `0` success
- `64` usage error (bad args, invalid glob/regex, unknown target, unresolved snapshot)
- `65` schema-version mismatch (the tool refuses to operate against unsupported `Configuration.Version`)
- `66` manifest/db unreadable, target disabled, snapshot id not found, path not in snapshot

When `--config` and `--db` are both omitted and `/run/duplicati-r2/config.json` is not readable to the invoker, the tool falls back to the default state directory `/var/lib/duplicati-r2/<slug>` and proceeds; pass `--config` or `--db` explicitly when the manifest layout is non-default.

## Extract a single file from R2 (Cut B)

`duplicati-r2-extract` (provided by `pkgs.duplicati-r2-tools.extract`) recovers a single file (or a glob set) from a chosen snapshot by fetching only the dblocks that contain the file's content blocks, decrypting them through the AES Crypt File Format wrapper, and writing the plaintext to a destination file, stdout, or an output directory in glob mode. Plaintext never persists outside the operator-chosen sink: the on-disk encrypted-block cache stores only ciphertext, and decryption streams through process memory.

Use `duplicati-r2-extract` instead of `duplicati-cli restore` when:

- the target is a single file (or a small glob), and
- the archive is too large to ever fully restore on this host (e.g. `bankdata` is 2.67 TiB encrypted on R2; the host has ~107 GiB free).

`duplicati-cli restore` remains the bulk-restore path documented above.

```bash
# Single-file extract to a path on disk (default snapshot = latest).
duplicati-r2-extract <slug> /abs/path/to/file --output /tmp/recovered

# Pipe to stdout for ad-hoc inspection.
duplicati-r2-extract <slug> /abs/path/to/file --output - | head -200

# Glob mode: mirror the snapshot tree under --output-dir.
duplicati-r2-extract <slug> --include '*.torrent' --output-dir /tmp/torrents

# Pin a specific snapshot.
duplicati-r2-extract <slug> /abs/path --output /tmp/out --snapshot 42

# Inspect an offline mirror (rsync of the bucket onto local NAS).
duplicati-r2-extract <slug> /abs/path --output /tmp/out --source file:///mnt/r2-mirror

# Print a JSON summary on stderr (plaintext still goes to the sink).
duplicati-r2-extract --json <slug> /abs/path --output /tmp/out
```

Flags worth knowing:

| Flag                            | Effect                                                                                                                                                                                                         |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--snapshot <id\|timestamp>`    | Resolve `Fileset.ID` integer or ISO-8601 timestamp; default is the latest snapshot.                                                                                                                            |
| `--output <path>` / `-o <path>` | Single-file destination. Use `-` for stdout. Required outside `--include` mode.                                                                                                                                |
| `--include <glob>`              | Path glob (fnmatch) selecting multiple files. Requires `--output-dir`. Patterns containing `/` are matched against full paths (`/data/*.bin`); patterns without `/` match the basename at any depth (`*.bin`). |
| `--output-dir <dir>`            | Mirror the snapshot tree under `<dir>` in glob mode. Snapshot paths containing `..` are refused.                                                                                                               |
| `--source <url>`                | Object source. Default: R2 via env-file credentials. Use `file:///path` for an offline mirror.                                                                                                                 |
| `--env-file <path>`             | Dotenv file with `R2_S3_ENDPOINT_URL`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `R2_BUCKET`, `DUPLICATI_PASSPHRASE` (default: `/etc/duplicati/r2.env`).                                                   |
| `--passphrase-env <VAR>`        | Read passphrase from named env var instead of `DUPLICATI_PASSPHRASE` in the env file. Skips env-file when paired with `--source file://`.                                                                      |
| `--cache-dir <path>`            | Encrypted-dblock cache root (default: `$XDG_CACHE_HOME/duplicati-r2-tools/<host>/<slug>/`).                                                                                                                    |
| `--cache-size <N[K\|M\|G]>`     | Cache size cap (default `1G`). `0` disables caching: every block re-fetches its dblock.                                                                                                                        |
| `--db`, `--config`, `--json`    | Same semantics as `duplicati-r2-list`.                                                                                                                                                                         |

Bucket layout resolution order:

- **hostname** prefix: `duplicati-r2-extract` resolves `DUPLICATI_R2_HOST` env override -> `manifest.hostname` -> `hostname --short` (Linux nodename truncated at first `.`). The backup script does not read `DUPLICATI_R2_HOST`; it resolves `manifest.hostname` -> `DEFAULT_HOSTNAME` (set by the systemd unit generator from `manifest.hostname`) -> `hostname --short`. They agree when `manifest.hostname` is set or both runs use the same host identity.
- **destSubpath** (per-target): `manifest.targets.<slug>.destSubpath` -> the slug. The backup script URL-encodes this inside the `s3://` URI; `duplicati-r2-extract` passes the raw decoded prefix to boto3 so both address the same R2 keys.
- **bucket**: `manifest.bucket` -> `R2_BUCKET` from the env file -> `duplicati-nixos-backups`.
- **endpoint URL**: `R2_S3_ENDPOINT_URL` from the env file -> `https://${R2_S3_ENDPOINT}` -> `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`.

Pass `--source file:///mirror` to bypass all of this (the file source maps `<root>/<volume_name>` directly).

Exit codes:

- `0` success
- `64` usage error (bad args, missing positional, path traversal in glob mode)
- `65` data error (HMAC mismatch on a dblock, manifest mismatch, FullHash mismatch, schema-version mismatch, wrong passphrase)
- `66` open error (env file unreadable, R2 GET failed, missing volume, path not in snapshot)

HMAC verification is non-optional: a corrupted dblock raises a loud `EXIT_DATA_ERR` with the offending volume name, never zero-fills or silently truncates.

### Env-file ACL

`/etc/duplicati/r2.env` carries the R2 access key pair and `DUPLICATI_PASSPHRASE`. The base mode stays `0400 root:root`. Each user listed in `services.duplicati-r2.stateDirReadableBy` is granted `u:<user>:r--` on the env file via a `systemd.tmpfiles` ACL rule, so `duplicati-r2-extract` can source credentials without sudo:

```bash
getfacl /etc/duplicati/r2.env | grep -E '^(user|mask)'
# Expect: user::r--, user:vx:r--, mask::r--
```

Other users still see `permission denied`. The grant is the same trust boundary that `stateDirReadableBy` already encodes for the SQLite databases.

### Cache footprint

The encrypted-dblock cache is an optimisation, never a requirement.

```bash
# Inspect the cache for a target.
ls -lh "$XDG_CACHE_HOME/duplicati-r2-tools/$(hostname)/<slug>/" \
  || ls -lh "$HOME/.cache/duplicati-r2-tools/$(hostname)/<slug>/"

# Drop the cache (every future read re-downloads).
rm -rf "$XDG_CACHE_HOME/duplicati-r2-tools/$(hostname)/<slug>"
```

The cache stores only encrypted bytes (mode `0600`); plaintext is never written to disk by the cache. Eviction is dblock-granular LRU. With the default `--cache-size 1G`, the cache rotates as new dblocks are fetched and the resident set stays bounded.

### Worked example: 44 `*.torrent` files from `bankdata`

Per [`../drafts/duplicati-r2-readonly-mount-investigation.md`](../drafts/duplicati-r2-readonly-mount-investigation.md) §9.8, a 44-path `*.torrent` recovery resolves to ~8 unique dblocks (~400 MiB encrypted) at default settings; `duplicati-cli restore` downloads each dblock as a single object. `duplicati-r2-extract` issues exactly the same fetch list (the SQL join is identical), with two operational wins: cache rotation between blocks within one dblock, and stream-to-disk decryption that never stages 400 MiB of encrypted bytes outside the cache cap.

```bash
duplicati-r2-extract bankdata --include '*.torrent' \
  --output-dir /tmp/torrent-recover --json
# Stderr summary reports plaintext_bytes, dblocks_fetched, bytes_fetched.
```

## Post-deploy checks

```bash
# Generator exited cleanly
systemctl status duplicati-r2-generate-units.service

# Runtime manifest is present
test -s /run/duplicati-r2/config.json && echo "manifest ok"

# All expected targets are scheduled
systemctl list-timers 'duplicati-r2-backup-*' 'duplicati-r2-verify-*'

# Per-target SQLite is reachable for the configured readers
ls -la /var/lib/duplicati-r2/
```

If a target unexpectedly fails to appear, the generator logged the reason to `journalctl -u duplicati-r2-generate-units.service` (typically a missing `onCalendar` or `enable: false`).

## Update a credential

Rotating an R2 access pair or any non-passphrase credential is safe:

```bash
nix develop -c sops -i secrets/duplicati-r2.yaml      # interactive edit
nixos-rebuild switch --flake .#<host>                  # or ./build.sh
```

The sops template that produces `/etc/duplicati/r2.env` declares `restartUnits = [ "duplicati-r2-generate-units.service" ]`, so the env file is regenerated and the next backup picks up the new credentials. Never rotate `DUPLICATI_PASSPHRASE` for a bucket that already holds backups.
