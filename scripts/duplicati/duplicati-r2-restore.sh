#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  cat <<'USAGE'
Usage: duplicati-r2-restore.sh [OPTIONS] <target-slug> <regex> [-- <duplicati-cli args>]

Restore files from a duplicati-r2 target whose paths match a POSIX regex.
The regex is auto-wrapped as duplicati's bracketed-regex filter form and
paired with a catch-all --exclude=*, so '.*\.torrent$' becomes:
  --include='[.*\.torrent$]' --exclude='*'
Without the paired exclude, Duplicati includes non-matching files by default.

Required positionals:
  <target-slug>            Target name as registered in the runtime manifest.
  <regex>                  POSIX (ERE) regex matched against full source paths.

Options:
  --dry-run                Compute matching files, dblocks, plaintext bytes,
                           and encrypted-fetch ceiling. Read-only against the
                           per-target SQLite. No restore, no network I/O.
  --restore-path <dir>     Output directory.
                           Default: /tmp/duplicati-restore/<slug>-<utc-ts>
                           A pre-existing non-empty directory is refused
                           unless --force is given.
  --chown <user:group>     Chown applied to the entries this restore wrote
                           (files restored and directories created), never to
                           pre-existing content. Default: vx:users.
                           Pass 'none' to skip the chown step.
  --force                  Allow restoring into a pre-existing non-empty
                           --restore-path. Restored entries can overwrite
                           files there (per --overwrite); chown/chmod stays
                           scoped to what the restore wrote.
  --version <n>            Snapshot version (0=latest, 1=second-latest, ...).
                           Mutually exclusive with --time.
  --time <iso>             Snapshot time as ISO-8601. Selects the most recent
                           snapshot at or before the given time. Mutually
                           exclusive with --version.
  --overwrite <bool>       Default: true. Pass false to keep timestamped copies.
  --log-level <level>      duplicati-cli console log level. Default: Information.
  -h, --help               Print this help and exit.
  --                       End of options. Remainder is passed to duplicati-cli.

Environment variables:
  DUPLICATI_R2_CONFIG      Override path to /run/duplicati-r2/config.json.
  DUPLICATI_R2_LOG_LEVEL   Default for --log-level.

Exit codes:
  0    success (or dry-run completed)
  64   usage error (bad arguments, mutually exclusive options, bad regex,
       pre-existing non-empty --restore-path without --force)
  66   manifest, env file, or db unreadable; target missing or disabled
  77   not running as root
  78   missing credentials in env file
  127  required command not found
  *    duplicati-cli exit code on failure

Notes on regex semantics:
  The script accepts POSIX ERE for the dry-run scan (matched in awk) and
  passes the same string to duplicati as a bracketed filter, which duplicati
  interprets via .NET regex. POSIX ERE and .NET regex are identical for
  common patterns (.*, ?, |, anchors, character classes); they diverge on
  advanced features (lookahead, named groups, etc.). Stick to the common
  subset for both engines to agree.

Examples:
  # Dry-run impact analysis: how many files match, how many dblocks must
  # be fetched, and how many encrypted bytes that ceiling represents.
  sudo ./duplicati-r2-restore.sh --dry-run bankdata '.*\.torrent$'

  # Restore .torrent files into the populated /data/torrent tree. --force
  # acknowledges the pre-existing content; chown/chmod touches only what the
  # restore writes.
  sudo ./duplicati-r2-restore.sh \
    --restore-path /data/torrent \
    --chown vx:users \
    --force \
    bankdata '.*\.torrent$'

  # Restore from a specific snapshot version.
  sudo ./duplicati-r2-restore.sh --version 1 bankdata '.*\.pdf$'

  # Restore from a snapshot at or before a given time.
  sudo ./duplicati-r2-restore.sh --time 2026-04-01T00:00:00Z bankdata '.*'

  # Pass extra args through to duplicati-cli.
  sudo ./duplicati-r2-restore.sh bankdata '.*' -- --restore-permissions=true
USAGE
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 127
  fi
}

require_cmd jq
require_cmd duplicati-cli
require_cmd sqlite3
require_cmd grep
require_cmd awk
require_cmd find
require_cmd numfmt
require_cmd hostname
require_cmd date
require_cmd mktemp
require_cmd sort
require_cmd comm
require_cmd xargs

human_bytes() {
  local n=${1:-0}
  numfmt --to=iec-i --suffix=B --format='%.1f' "$n" 2>/dev/null || echo "${n}B"
}

dry_run=false
force=false
restore_path=""
chown_spec="vx:users"
version_arg=""
time_arg=""
overwrite="true"
log_level="${DUPLICATI_R2_LOG_LEVEL:-Information}"
slug=""
user_regex=""
declare -a passthrough=()
declare -a positional=()

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run)
    dry_run=true
    shift
    ;;
  --force)
    force=true
    shift
    ;;
  --restore-path)
    restore_path=$2
    shift 2
    ;;
  --restore-path=*)
    restore_path=${1#*=}
    shift
    ;;
  --chown)
    chown_spec=$2
    shift 2
    ;;
  --chown=*)
    chown_spec=${1#*=}
    shift
    ;;
  --version)
    version_arg=$2
    shift 2
    ;;
  --version=*)
    version_arg=${1#*=}
    shift
    ;;
  --time)
    time_arg=$2
    shift 2
    ;;
  --time=*)
    time_arg=${1#*=}
    shift
    ;;
  --overwrite)
    overwrite=$2
    shift 2
    ;;
  --overwrite=*)
    overwrite=${1#*=}
    shift
    ;;
  --log-level)
    log_level=$2
    shift 2
    ;;
  --log-level=*)
    log_level=${1#*=}
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --)
    shift
    passthrough+=("$@")
    break
    ;;
  -*)
    echo "unknown option: $1" >&2
    usage >&2
    exit 64
    ;;
  *)
    positional+=("$1")
    shift
    ;;
  esac
done

if [[ ${#positional[@]} -ne 2 ]]; then
  echo "expected exactly two positional args (slug and regex), got ${#positional[@]}" >&2
  usage >&2
  exit 64
fi

slug=${positional[0]}
user_regex=${positional[1]}

if [[ -z $slug ]]; then
  echo "target slug must not be empty" >&2
  exit 64
fi

if [[ -z $user_regex ]]; then
  echo "regex must not be empty" >&2
  exit 64
fi

if [[ -n $version_arg && -n $time_arg ]]; then
  echo "--version and --time are mutually exclusive" >&2
  exit 64
fi

if [[ -n $version_arg && ! $version_arg =~ ^[0-9]+$ ]]; then
  echo "--version must be a non-negative integer, got '$version_arg'" >&2
  exit 64
fi

# Validate regex up front so we exit before any privileged action.
regex_err=$(printf '' | grep -E -- "$user_regex" 2>&1 >/dev/null) || true
if [[ -n $regex_err ]]; then
  echo "invalid POSIX regex: $regex_err" >&2
  exit 64
fi

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "duplicati-r2-restore.sh must be run as root" >&2
  exit 77
fi

config_path="${DUPLICATI_R2_CONFIG:-/run/duplicati-r2/config.json}"
if [[ ! -r $config_path ]]; then
  echo "unable to read Duplicati config at $config_path" >&2
  exit 66
fi

if ! jq -e --arg slug "$slug" '.targets[$slug]' "$config_path" >/dev/null 2>&1; then
  echo "target '$slug' not found in $config_path" >&2
  exit 66
fi

target_enabled=$(jq -r --arg slug "$slug" '.targets[$slug].enable // true' "$config_path")
if [[ $target_enabled != "true" ]]; then
  echo "target '$slug' is disabled (enable: $target_enabled). Refusing to restore." >&2
  exit 66
fi

target_json=$(jq --arg slug "$slug" -c '.targets[$slug]' "$config_path")

env_file=$(jq -r --arg slug "$slug" \
  '.targets[$slug].environmentFile // .environmentFile // "/etc/duplicati/r2.env"' \
  "$config_path")

if [[ ! -f $env_file ]]; then
  echo "missing environment file $env_file" >&2
  exit 66
fi

bucket=$(jq -r --arg slug "$slug" \
  '.targets[$slug].bucket // .bucket // "duplicati-nixos-backups"' \
  "$config_path")
dest_subpath=$(jq -r --arg slug "$slug" '.destSubpath // $slug' <<<"$target_json")
state_dir=$(jq -r --arg slug "$slug" \
  '.targets[$slug].stateDir // .stateDir // "/var/lib/duplicati-r2"' \
  "$config_path")
manifest_hostname=$(jq -r '.hostname // empty' "$config_path")

db_slug=$(jq -rn --arg s "$slug" '$s | gsub("[^A-Za-z0-9_\\-]"; "-")')
db_path="${state_dir}/duplicati-r2-${db_slug}.sqlite"

hostname_value="$manifest_hostname"
if [[ -z ${hostname_value:-} ]]; then
  if [[ -n ${DEFAULT_HOSTNAME:-} ]]; then
    hostname_value="$DEFAULT_HOSTNAME"
  else
    hostname_value=$(hostname --short 2>/dev/null || hostname 2>/dev/null || echo duplicati)
  fi
fi

declare -a extra_args_raw=()
mapfile -t extra_args_raw < <(jq -r '.extraArgs // [] | .[]' <<<"$target_json") || extra_args_raw=()
declare -a extra_args=()
for arg in "${extra_args_raw[@]}"; do
  [[ -n $arg ]] && extra_args+=("$arg")
done

# shellcheck source=/dev/null disable=SC1091
. "$env_file"

if [[ -z ${AWS_ACCESS_KEY_ID:-} || -z ${AWS_SECRET_ACCESS_KEY:-} ]]; then
  echo "AWS credentials missing in $env_file" >&2
  exit 78
fi

if [[ -z ${DUPLICATI_PASSPHRASE:-} ]]; then
  echo "DUPLICATI_PASSPHRASE missing in $env_file" >&2
  exit 78
fi

# duplicati's S3 backend reads creds from AUTH_USERNAME/AUTH_PASSWORD; without
# the alias it fails with S3NoAmzUserID despite the AWS_* vars being set.
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
export AUTH_USERNAME="$AWS_ACCESS_KEY_ID" AUTH_PASSWORD="$AWS_SECRET_ACCESS_KEY"
# duplicati-cli accepts --passphrase on the CLI or via the PASSPHRASE env var.
# Use the env var: cmdline args are world-readable via /proc/<pid>/cmdline.
export DUPLICATI_PASSPHRASE PASSPHRASE="$DUPLICATI_PASSPHRASE"

if [[ -n ${R2_S3_ENDPOINT_URL:-} ]]; then
  export AWS_ENDPOINT_URL="$R2_S3_ENDPOINT_URL"
elif [[ -n ${R2_S3_ENDPOINT:-} ]]; then
  export AWS_ENDPOINT_URL="https://${R2_S3_ENDPOINT}"
fi

if [[ -z ${AWS_REGION:-} && -z ${AWS_DEFAULT_REGION:-} ]]; then
  if [[ -n ${R2_REGION:-} ]]; then
    export AWS_REGION="$R2_REGION" AWS_DEFAULT_REGION="$R2_REGION"
  else
    export AWS_REGION=auto AWS_DEFAULT_REGION=auto
  fi
fi

server_name=""
if [[ -n ${R2_S3_ENDPOINT:-} ]]; then
  server_name="$R2_S3_ENDPOINT"
elif [[ -n ${R2_S3_ENDPOINT_URL:-} ]]; then
  server_name=${R2_S3_ENDPOINT_URL#https://}
  server_name=${server_name#http://}
elif [[ -n ${AWS_ENDPOINT_URL:-} ]]; then
  server_name=${AWS_ENDPOINT_URL#https://}
  server_name=${server_name#http://}
fi
if [[ -z $server_name ]]; then
  echo "could not resolve R2 endpoint hostname (set R2_S3_ENDPOINT or R2_S3_ENDPOINT_URL)" >&2
  exit 66
fi

encoded_subpath=$(jq -rn --arg s "$dest_subpath" '$s | @uri')

# AWS S3 client + R2 quirk flags + connection-pool tunables.
# - s3-disable-chunk-encoding / s3-disable-payload-signing: R2 PUT-side
#   workarounds; harmless on read paths but protect implicit recreate writes.
# - s3-ext-disablehostprefixinjection: defensive against AWS-SDK's bucket
#   host-prefix logic for non-AWS endpoints.
# - s3-ext-buffersize=4194304: 4 MiB socket buffer; lifts single-stream
#   throughput on the R2 high-BDP path.
# - s3-ext-httpclientcachesize=4 + maxconnectionsperserver=8: gives the SDK
#   independent connection pools so concurrent requests use distinct sockets,
#   which restore's 8-deep pipeline can fan out over.
# s3-ext-forcepathstyle=true is auto-set inside S3Backend.cs for non-amazonaws
# hosts; no need to specify here.
dest="s3://${bucket}/${hostname_value}/${encoded_subpath}\
?use-ssl=true\
&s3-server-name=${server_name}\
&s3-client=aws\
&s3-disable-chunk-encoding=true\
&s3-disable-payload-signing=true\
&s3-ext-disablehostprefixinjection=true\
&s3-ext-buffersize=4194304\
&s3-ext-httpclientcachesize=4\
&s3-ext-maxconnectionsperserver=8"

if [[ -z $restore_path ]]; then
  ts=$(date -u +%Y%m%dT%H%M%SZ)
  restore_path="/tmp/duplicati-restore/${slug}-${ts}"
fi

cat <<INFO
Target         : ${slug}
Config         : ${config_path}
Environment    : ${env_file}
Database       : ${db_path}
Bucket         : ${bucket}
Hostname       : ${hostname_value}
Destination    : ${dest}
Regex          : ${user_regex}
Restore path   : ${restore_path}
Chown          : ${chown_spec}
Log level      : ${log_level}
Overwrite      : ${overwrite}
INFO
[[ -n $version_arg ]] && echo "Version        : ${version_arg}"
[[ -n $time_arg ]] && echo "Time           : ${time_arg}"
if [[ ${#extra_args[@]} -gt 0 ]]; then
  printf 'Manifest extra : %s\n' "${extra_args[*]}"
fi
if [[ ${#passthrough[@]} -gt 0 ]]; then
  printf 'Passthrough    : %s\n' "${passthrough[*]}"
fi
echo

# === Dry-run path ===
if "$dry_run"; then
  if [[ ! -r $db_path ]]; then
    echo "db not readable at $db_path -- cannot perform dry-run analysis" >&2
    echo "(without the local db, restore would trigger an implicit recreate)" >&2
    exit 66
  fi

  src_uri="file:${db_path}?mode=ro&immutable=1&nolock=1"

  if [[ -n $version_arg ]]; then
    fileset_id=$(sqlite3 "$src_uri" "SELECT ID FROM Fileset ORDER BY Timestamp DESC LIMIT 1 OFFSET ${version_arg};")
  elif [[ -n $time_arg ]]; then
    epoch=$(date -d "$time_arg" +%s 2>/dev/null) || {
      echo "could not parse --time '$time_arg'" >&2
      exit 64
    }
    fileset_id=$(sqlite3 "$src_uri" "SELECT ID FROM Fileset WHERE Timestamp <= ${epoch} ORDER BY Timestamp DESC LIMIT 1;")
  else
    fileset_id=$(sqlite3 "$src_uri" "SELECT ID FROM Fileset ORDER BY Timestamp DESC LIMIT 1;")
  fi

  if [[ -z $fileset_id ]]; then
    echo "no fileset matched the version/time selector" >&2
    exit 66
  fi

  fileset_ts=$(sqlite3 "$src_uri" "SELECT datetime(Timestamp, 'unixepoch') FROM Fileset WHERE ID = ${fileset_id};")
  echo "Fileset        : ID=${fileset_id} (${fileset_ts} UTC)"
  echo

  scratch=$(mktemp -d -t duplicati-restore-dryrun.XXXXXX)
  trap 'rm -rf "$scratch"' EXIT
  ids_file="${scratch}/ids.tsv"

  echo "Scanning fileset for matching paths..."
  sqlite3 -separator $'\t' -noheader "$src_uri" "
    SELECT f.ID, f.Path
    FROM File f
    JOIN FilesetEntry fse ON fse.FileID = f.ID
    WHERE fse.FilesetID = ${fileset_id};
  " | awk -v re="$user_regex" -F'\t' '{ id=$1; sub(/^[^\t]*\t/, ""); if ($0 ~ re) print id }' >"$ids_file"

  match_count=$(wc -l <"$ids_file" | awk '{print $1}')

  if [[ $match_count -eq 0 ]]; then
    echo "Files matched  : 0"
    echo
    echo "(no impact analysis run; no files match the regex)"
    exit 0
  fi

  # Run impact join via a fresh sqlite3 invocation that ATTACHes the live db
  # read-only and imports the matching IDs into a temp table. Capture output
  # and status separately: a here-string read would succeed on the empty line
  # a failed sqlite3 leaves behind and report garbage counts as a clean run.
  if ! impact_output=$(
    sqlite3 -separator ' ' -noheader <<SQL
ATTACH DATABASE '${src_uri}' AS src;
CREATE TEMP TABLE matching_ids (ID INTEGER PRIMARY KEY);
.mode tabs
.import "${ids_file}" matching_ids
WITH matching_blocks AS (
  SELECT DISTINCT bk.VolumeID, rv.Name, rv.Size, rv.State
  FROM matching_ids m
  JOIN src.File f          ON f.ID         = m.ID
  JOIN src.BlocksetEntry be ON be.BlocksetID = f.BlocksetID
  JOIN src.Block bk        ON bk.ID        = be.BlockID
  JOIN src.Remotevolume rv ON rv.ID        = bk.VolumeID
  WHERE rv.State IN ('Verified', 'Uploaded')
)
SELECT
  COALESCE((SELECT SUM(b.Length)
              FROM matching_ids m
              JOIN src.File f     ON f.ID = m.ID
              JOIN src.Blockset b ON b.ID = f.BlocksetID), 0),
  (SELECT COUNT(*) FROM matching_blocks),
  COALESCE((SELECT SUM(Size) FROM matching_blocks), 0),
  (SELECT COUNT(*) FROM matching_blocks WHERE State = 'Uploaded');
SQL
  ); then
    echo "impact analysis query failed (sqlite3 exit $?); db locked, corrupt, or schema drift?" >&2
    exit 66
  fi

  read -r plaintext_bytes dblocks encrypted_bytes orphans <<<"$impact_output"

  if [[ ! ${plaintext_bytes:-} =~ ^[0-9]+$ || ! ${dblocks:-} =~ ^[0-9]+$ ||
    ! ${encrypted_bytes:-} =~ ^[0-9]+$ || ! ${orphans:-} =~ ^[0-9]+$ ]]; then
    echo "impact analysis returned non-numeric output: '${impact_output}'" >&2
    exit 66
  fi

  printf 'Files matched  : %s\n' "$match_count"
  printf 'Plaintext bytes: %s (%s)\n' "$plaintext_bytes" "$(human_bytes "$plaintext_bytes")"
  printf 'Unique dblocks : %s\n' "$dblocks"
  printf 'Fetch ceiling  : %s (%s, encrypted)\n' "$encrypted_bytes" "$(human_bytes "$encrypted_bytes")"

  if [[ ${orphans:-0} -gt 0 ]]; then
    echo
    echo "WARNING: ${orphans} of the matched dblocks have State='Uploaded' (not yet 'Verified')."
    echo "  These can 404 on R2 if multipart uploads were aborted before completion."
    echo "  See docs/duplicati/recovery.md for the multipart-orphan signature."
  fi

  exit 0
fi

# === Real-run path ===

if [[ ! -r $db_path ]]; then
  echo "WARNING: local db at $db_path is missing or unreadable."
  echo "  duplicati-cli will trigger an implicit recreate, downloading every dindex."
  echo "  This can take hours on a multi-TiB archive at single-stream R2 throughput."
  echo "  Consider restoring the per-target SQLite from a sidecar copy first."
  echo
fi

restore_path_preexisting=false
if [[ -e $restore_path ]]; then
  if [[ ! -d $restore_path ]]; then
    echo "--restore-path exists and is not a directory: $restore_path" >&2
    exit 64
  fi
  restore_path_preexisting=true
  if [[ -n $(find "$restore_path" -mindepth 1 -print -quit) && $force != true ]]; then
    echo "refusing: --restore-path '$restore_path' already exists and is not empty." >&2
    echo "  A restore into it can overwrite files (per --overwrite) and the post-restore" >&2
    echo "  ownership/permission pass would mix with pre-existing content." >&2
    echo "  Re-run with --force to accept that, or pass a fresh directory." >&2
    exit 64
  fi
fi

mkdir -p "$restore_path"

# Marker plus pre-existing-directory inventory scope the post-restore chown
# and chmod to entries this restore writes. Restored files get a fresh ctime
# (newer than the marker's mtime); duplicati also bumps the ctime of
# pre-existing directories it writes into, so those are excluded through the
# inventory instead of being re-owned as a side effect.
scope_dir=$(mktemp -d -t duplicati-restore-scope.XXXXXX)
trap 'rm -rf "$scope_dir"' EXIT
restore_marker="${scope_dir}/marker"
pre_dirs="${scope_dir}/pre-dirs"
: >"$restore_marker"
find "$restore_path" -mindepth 1 -type d -print0 | LC_ALL=C sort -z >"$pre_dirs"

restored_entries() {
  find "$restore_path" -mindepth 1 -type f -cnewer "$restore_marker" -print0
  find "$restore_path" -mindepth 1 -type d -cnewer "$restore_marker" -print0 |
    LC_ALL=C sort -z | comm -z -23 - "$pre_dirs"
}

declare -a restore_args=(
  "$dest"
  "--dbpath=${db_path}"
  "--restore-path=${restore_path}"
  "--include=[${user_regex}]"
  "--exclude=*"
  "--console-log-level=${log_level}"
  "--overwrite=${overwrite}"
  "--restore-volume-downloaders=8"
  "--restore-volume-decryptors=8"
  "--restore-volume-decompressors=8"
  "--restore-channel-buffer-size=32"
)
[[ -n $version_arg ]] && restore_args+=("--version=${version_arg}")
[[ -n $time_arg ]] && restore_args+=("--time=${time_arg}")
if [[ ${#extra_args[@]} -gt 0 ]]; then
  restore_args+=("${extra_args[@]}")
fi
if [[ ${#passthrough[@]} -gt 0 ]]; then
  restore_args+=("${passthrough[@]}")
fi

echo ">>> duplicati-cli restore ..."
start=$(date +%s)
set +e
duplicati-cli restore "${restore_args[@]}"
rc=$?
set -e
end=$(date +%s)
elapsed=$((end - start))

if [[ $rc -ne 0 ]]; then
  echo "duplicati-cli restore failed with exit code $rc after ${elapsed}s" >&2
  exit "$rc"
fi

if [[ $chown_spec != "none" ]]; then
  echo
  echo "Applying chown ${chown_spec} to restored entries under ${restore_path}..."
  restored_entries | xargs -0 -r chown "$chown_spec"
  if [[ $restore_path_preexisting == false ]]; then
    chown "$chown_spec" "$restore_path"
  fi
fi

# Restore drops the owner write bit on dirs and files because duplicati's
# WriteMetadata applies CoreAttributes (FileAttributes.ReadOnly) unconditionally
# (FileRestoreDestinationProvider.cs), which on Linux translates to clearing
# the write bits. --restore-permissions=false does NOT suppress this; it only
# gates the unix-mode/uid/gid path. Re-grant owner rwX and strip group/other
# so the tree is usable post-chown without widening exposure. Scoped to the
# restored entries so pre-existing content keeps its modes.
echo "Resetting permissions to u+rwX,go-rwx on restored entries under ${restore_path}..."
restored_entries | xargs -0 -r chmod u+rwX,go-rwx
if [[ $restore_path_preexisting == false ]]; then
  chmod u+rwX,go-rwx "$restore_path"
fi

echo
echo "Restored files under ${restore_path}:"
find "$restore_path" -type f -cnewer "$restore_marker" -printf '  %p (%s bytes)\n' 2>/dev/null | sort || true

echo
printf 'Done in %ss.\n' "$elapsed"
