#!/usr/bin/env bash

set -euo pipefail

if [[ ${1-} ]]; then
  REPO_ROOT=$(realpath "$1")
else
  REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)
fi

REGISTRY_DEFAULT="$REPO_ROOT/docs/RFC-0001/manifest-registry.json"
REGISTRY="${HOST_PACKAGE_GUARD_REGISTRY:-$REGISTRY_DEFAULT}"
ACTUAL_JSON_PATH="${HOST_PACKAGE_GUARD_ACTUAL_JSON:-}"

if [[ ! -f $REGISTRY ]]; then
  echo "host-package-guard: manifest registry not found at $REGISTRY" >&2
  exit 1
fi

if [[ -z $ACTUAL_JSON_PATH || ! -f $ACTUAL_JSON_PATH ]]; then
  echo "host-package-guard: precomputed package list not found at \$HOST_PACKAGE_GUARD_ACTUAL_JSON (${ACTUAL_JSON_PATH:-unset})" >&2
  exit 1
fi

export NIX_CONFIG="${NIX_CONFIG:-experimental-features = nix-command flakes}"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

jq -c '.[]' "$REGISTRY" >"$tmpdir/entries.json"

role_inventory="${HOST_PACKAGE_GUARD_ROLE_INVENTORY:-}"
if [[ -z $role_inventory ]]; then
  role_inventory="$tmpdir/role-inventory.json"
  python3 "$REPO_ROOT/scripts/list-role-imports.py" --offline --repo "$REPO_ROOT" --format json >"$role_inventory"
fi

if [[ ! -s $role_inventory ]]; then
  echo "host-package-guard: role import inventory is empty; cannot compute allowlist" >&2
  exit 1
fi
PACKAGE_UTILS="$REPO_ROOT/scripts/package_utils.py"

allowed_sorted="$tmpdir/allowed.txt"
python3 "$PACKAGE_UTILS" normalize --mode role-inventory --input "$role_inventory" --output "$allowed_sorted"

status=0

while IFS= read -r entry; do
  host=$(jq -r '.host // empty' <<<"$entry")
  manifest_rel=$(jq -r '.manifest' <<<"$entry")

  if [[ -z $manifest_rel ]]; then
    echo "host-package-guard: registry entry missing manifest" >&2
    status=1
    continue
  fi

  if [[ -z $host ]]; then
    echo "host-package-guard: skipping entry without host binding ($manifest_rel)" >&2
    continue
  fi

  manifest="$REPO_ROOT/$manifest_rel"
  if [[ ! -f $manifest ]]; then
    echo "host-package-guard: manifest $manifest not found" >&2
    status=1
    continue
  fi

  manifest_sorted="$tmpdir/${host}-expected.txt"
  python3 "$PACKAGE_UTILS" normalize --mode manifest --input "$manifest" --output "$manifest_sorted"

  actual_sorted="$tmpdir/${host}-actual.txt"
  if ! python3 "$PACKAGE_UTILS" normalize --mode actual --input "$ACTUAL_JSON_PATH" --host "$host" --output "$actual_sorted"; then
    status=1
    continue
  fi

  missing=$(comm -23 "$manifest_sorted" "$actual_sorted" || true)
  unexpected=$(comm -13 "$manifest_sorted" "$actual_sorted" || true)

  if [[ -n $missing || -n $unexpected ]]; then
    status=1
    echo "host-package-guard: ${host} diverges from $manifest_rel" >&2
    if [[ -n $missing ]]; then
      echo "  missing:" >&2
      echo "$missing" >&2
    fi
    if [[ -n $unexpected ]]; then
      echo "  unexpected:" >&2
      echo "$unexpected" >&2
    fi
  fi

  untracked=$(comm -13 "$allowed_sorted" "$actual_sorted" || true)
  if [[ -n $untracked ]]; then
    status=1
    echo "host-package-guard: ${host} includes packages not covered by roles" >&2
    echo "  untracked:" >&2
    echo "$untracked" >&2
  fi
done <"$tmpdir/entries.json"

exit $status
