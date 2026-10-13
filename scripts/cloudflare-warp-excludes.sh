#!/usr/bin/env bash
# Converges the split-tunnel exclude lists of the default WARP device profile
# and of every nixos-<host> profile on the declared lists: the base list the
# package passes in, plus <host>.exclude from secrets/cloudflare-warp.yaml.
set -euo pipefail
shopt -s inherit_errexit

usage() {
  cat <<'EOF'
Usage: cloudflare-warp-excludes [--apply]

Prints how the exclude list of the default WARP device profile and of each
nixos-<host> profile differs from the declared list: the base list in
modules/apps/cloudflare-warp/excludes-package.nix, plus <host>.exclude in
secrets/cloudflare-warp.yaml for a host profile. --apply replaces every list
that differs. Run from the repository root.
EOF
}

apply=false
case "${1:-}" in
"") ;;
--apply) apply=true ;;
-h | --help)
  usage
  exit 0
  ;;
*)
  usage >&2
  exit 2
  ;;
esac

base_file=${CLOUDFLARE_WARP_BASE_EXCLUDES:?set by the cloudflare-warp-excludes package}
secrets_file=secrets/cloudflare-warp.yaml
if [[ ! -f $secrets_file ]]; then
  echo "cloudflare-warp-excludes: $secrets_file not found; run from the repository root" >&2
  exit 1
fi

secrets=$(sops -d --output-type json "$secrets_file")
base=$(jq -c . "$base_file")
api="https://api.cloudflare.com/client/v4/accounts/$(jq -er .account_id <<<"$secrets")/devices"

# The bearer header goes through a file descriptor so the token stays out of argv.
cf() {
  local method=$1 path=$2 response
  shift 2
  response=$(curl -sS -X "$method" "$@" \
    -H @<(jq -r '"Authorization: Bearer \(.zero_trust_api_token)"' <<<"$secrets") \
    -H 'Content-Type: application/json' "$api$path")
  if ! jq -e .success <<<"$response" >/dev/null; then
    echo "cloudflare-warp-excludes: $method $path failed: $(jq -c .errors <<<"$response")" >&2
    return 1
  fi
  jq -c .result <<<"$response"
}

# Cloudflare returns a list in its own order, so the two compare as sets.
changes() {
  jq -rs '
    def canon: map(with_entries(select(.value != null and .value != "")) | tojson) | sort;
    (.[0] | canon) as $want | (.[1] | canon) as $have
    | (($want - $have)[] | "  + \(.)"), (($have - $want)[] | "  - \(.)")
  ' <<<"$1$2"
}

pending=0
replaced=0
converge() {
  local label=$1 path=$2 want=$3 have diff
  have=$(cf GET "$path")
  diff=$(changes "$want" "$have")
  if [[ -z $diff ]]; then
    echo "$label: up to date"
    return 0
  fi
  echo "$label:"
  echo "$diff"
  if $apply; then
    cf PUT "$path" --data-binary @- <<<"$want" >/dev/null
    echo "$label: replaced"
    replaced=$((replaced + 1))
  else
    pending=$((pending + 1))
  fi
}

policies=$(cf GET /policies)
mapfile -t hosts < <(jq -r 'to_entries[] | select(.value | type == "object" and has("auth_client_id")) | .key' <<<"$secrets")

converge default /policy/exclude "$base"
for host in "${hosts[@]}"; do
  id=$(jq -r --arg name "nixos-$host" '.[] | select(.name == $name) | .policy_id' <<<"$policies")
  if [[ -z $id ]]; then
    echo "cloudflare-warp-excludes: no device profile named nixos-$host" >&2
    exit 1
  fi
  converge "nixos-$host" "/policy/$id/exclude" \
    "$(jq -c --arg host "$host" --argjson base "$base" '$base + (.[$host].exclude // [])' <<<"$secrets")"
done

if ((pending > 0)); then
  echo "Run with --apply to replace $pending list(s)."
fi
if ((replaced > 0)); then
  echo "warp-svc can keep the previous list until restarted: sudo systemctl restart cloudflare-warp.service"
fi
