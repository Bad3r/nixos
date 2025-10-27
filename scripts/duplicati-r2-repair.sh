#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: duplicati-r2-repair.sh [--list-broken-files] [--purge-broken-files] [--rebuild-missing-dblocks] <target-slug> [-- <duplicati-cli args>]

Flags:
  --list-broken-files        Run duplicati-cli list-broken-files instead of repair.
  --purge-broken-files       Run duplicati-cli purge-broken-files (always runs list-broken-files first).
  --rebuild-missing-dblocks  Add --rebuild-missing-dblock-files=true when running repair.

Environment variables:
  DUPLICATI_R2_CONFIG    Override path to the rendered Duplicati config (default: /run/duplicati-r2/config.json)

Examples:
  sudo ./duplicati-r2-repair.sh bankdata
  sudo ./duplicati-r2-repair.sh --list-broken-files bankdata
  sudo ./duplicati-r2-repair.sh --purge-broken-files bankdata -- --dry-run
  sudo DUPLICATI_R2_CONFIG=/path/to/config ./duplicati-r2-repair.sh bankdata -- --no-auto-compact
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

log_level="${DUPLICATI_R2_LOG_LEVEL:-Warning}"

list_broken=false
purge_broken=false
rebuild_dblocks=false
target=""
passthrough=()

while [[ $# -gt 0 ]]; do
  case "$1" in
  --list-broken-files)
    list_broken=true
    shift
    ;;
  --purge-broken-files)
    purge_broken=true
    list_broken=true
    shift
    ;;
  --rebuild-missing-dblocks)
    rebuild_dblocks=true
    shift
    ;;
  --help | -h)
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
    if [[ -n $target ]]; then
      echo "target already specified: $target (saw '$1')" >&2
      exit 64
    fi
    target="$1"
    shift
    ;;
  esac

done

if [[ -z $target ]]; then
  usage >&2
  exit 64
fi

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "duplicati-r2-repair.sh must be run as root" >&2
  exit 77
fi

config_path="${DUPLICATI_R2_CONFIG:-/run/duplicati-r2/config.json}"

if [[ ! -r $config_path ]]; then
  echo "unable to read Duplicati config at $config_path" >&2
  exit 66
fi

if ! jq -e --arg slug "$target" '.targets[$slug]' "$config_path" >/dev/null 2>&1; then
  echo "target '$target' not found in $config_path" >&2
  exit 66
fi

target_json=$(jq --arg slug "$target" -c '.targets[$slug]' "$config_path")

env_file=$(jq -r --arg slug "$target" '.targets[$slug].environmentFile // .environmentFile // "/etc/duplicati/r2.env"' "$config_path")

if [[ ! -f $env_file ]]; then
  echo "missing environment file $env_file" >&2
  exit 66
fi

bucket=$(jq -r --arg slug "$target" '.targets[$slug].bucket // .bucket // "duplicati-nixos-backups"' "$config_path")
dest_subpath=$(jq -r --arg slug "$target" '.destSubpath // $slug' <<<"$target_json")
state_dir=$(jq -r --arg slug "$target" '.targets[$slug].stateDir // .stateDir // "/var/lib/duplicati-r2"' "$config_path")
manifest_hostname=$(jq -r '.hostname // empty' "$config_path")

db_slug=$(jq -rn --arg s "$target" '$s | gsub("[^A-Za-z0-9_\\-]"; "-")')
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

# shellcheck disable=SC1091
. "$env_file"

if [[ -z ${AWS_ACCESS_KEY_ID:-} || -z ${AWS_SECRET_ACCESS_KEY:-} ]]; then
  echo "AWS credentials missing in $env_file" >&2
  exit 78
fi

if [[ -z ${DUPLICATI_PASSPHRASE:-} ]]; then
  echo "DUPLICATI_PASSPHRASE missing in $env_file" >&2
  exit 78
fi

export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
export AUTH_USERNAME="$AWS_ACCESS_KEY_ID" AUTH_PASSWORD="$AWS_SECRET_ACCESS_KEY"
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

encoded_subpath=$(jq -rn --arg s "$dest_subpath" '$s | @uri')

server_param=""
if [[ -n ${R2_S3_ENDPOINT:-} ]]; then
  server_param="&s3-server-name=${R2_S3_ENDPOINT}"
elif [[ -n ${R2_S3_ENDPOINT_URL:-} ]]; then
  server_host=${R2_S3_ENDPOINT_URL#https://}
  server_host=${server_host#http://}
  server_param="&s3-server-name=${server_host}"
elif [[ -n ${AWS_ENDPOINT_URL:-} ]]; then
  server_host=${AWS_ENDPOINT_URL#https://}
  server_host=${server_host#http://}
  server_param="&s3-server-name=${server_host}"
fi

region_suffix=""
if [[ -n ${R2_REGION:-} ]]; then
  region_suffix="&s3-ext-region=${R2_REGION}"
fi

dest="s3://${bucket}/${hostname_value}/${encoded_subpath}?use-ssl=true&s3-ext-disablehostprefixinjection=true&s3-disable-chunk-encoding=true&s3-client=minio${server_param}${region_suffix}"

echo "Target         : ${target}"
echo "Config         : ${config_path}"
echo "Environment    : ${env_file}"
echo "Database       : ${db_path}"
echo "Destination    : ${dest}"
if [[ ${#extra_args[@]} -gt 0 ]]; then
  printf 'Extra args     : %s\n' "${extra_args[*]}"
fi
if [[ ${#passthrough[@]} -gt 0 ]]; then
  printf 'CLI passthrough: %s\n' "${passthrough[*]}"
fi

common_args=("$dest" "--dbpath=${db_path}")
[[ ${#extra_args[@]} -gt 0 ]] && common_args+=("${extra_args[@]}")
[[ ${#passthrough[@]} -gt 0 ]] && common_args+=("${passthrough[@]}")

run_cli() {
  local subcommand=$1
  shift
  echo
  echo ">>> duplicati-cli ${subcommand} ..."
  duplicati-cli "$subcommand" "$@"
}

print_summary_if_present() {
  local file=$1
  local summary
  summary=$(grep -E 'Found .*broken|Found .*missing remote files|Missing file:' "$file" || true)
  if [[ -n $summary ]]; then
    echo "$summary"
  fi
}

if [[ -n ${region_suffix} ]]; then
  echo "warning: --s3-ext-region is not supported by duplicati-cli and will be ignored" >&2
fi

if "$list_broken"; then
  list_args=("${common_args[@]}" "--console-log-level=${log_level}")
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' EXIT
  echo
  echo ">>> duplicati-cli list-broken-files ..."
  duplicati-cli list-broken-files "${list_args[@]}" | tee "$tmp"
  status=$?
  if [[ $status -ne 0 ]]; then
    echo "duplicati-cli list-broken-files failed with exit code $status" >&2
    rm -f "$tmp"
    trap - EXIT
    exit $status
  fi
  print_summary_if_present "$tmp"
  rm -f "$tmp"
  trap - EXIT
fi

if "$purge_broken"; then
  purge_args=("${common_args[@]}" "--console-log-level=${log_level}")
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' EXIT
  echo
  echo ">>> duplicati-cli purge-broken-files ..."
  duplicati-cli purge-broken-files "${purge_args[@]}" | tee "$tmp"
  status=$?
  if [[ $status -ne 0 ]]; then
    echo "duplicati-cli purge-broken-files failed with exit code $status" >&2
    rm -f "$tmp"
    trap - EXIT
    exit $status
  fi
  print_summary_if_present "$tmp"
  rm -f "$tmp"
  trap - EXIT
else
  if ! "$list_broken"; then
    repair_args=("${common_args[@]}")
    if "$rebuild_dblocks"; then
      repair_args+=("--rebuild-missing-dblock-files=true")
    fi
    run_cli repair "${repair_args[@]}"
  fi
fi
