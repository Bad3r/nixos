#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

root=$(git rev-parse --show-toplevel)
cd "$root"

fetch=0
while [ $# -gt 0 ]; do
  case "$1" in
  --fetch)
    fetch=1
    ;;
  --no-fetch)
    fetch=0
    ;;
  *)
    echo "usage: check-maintained-inputs.sh [--fetch|--no-fetch]" >&2
    exit 2
    ;;
  esac
  shift
done

if [ "${MAINTAINED_INPUTS_FETCH:-0}" = "1" ]; then
  fetch=1
fi

tmp_root=$(mktemp -d)
inventory_json="$tmp_root/inventory.json"
flake_inputs_json="$tmp_root/flake-inputs.json"

# shellcheck disable=SC2329
cleanup_tmp_root() {
  local status=$?
  if [ -d "$tmp_root" ]; then
    chmod -R u+w "$tmp_root" 2>/dev/null || true
    if ! rm -r "$tmp_root"; then
      printf 'maintained-inputs: warning: failed to remove temporary directory %s\n' "$tmp_root" >&2
    fi
  fi
  exit "$status"
}
trap cleanup_tmp_root EXIT

fail=0

error_msg() {
  printf 'maintained-inputs: %s\n' "$*" >&2
  fail=1
}

# Committed flake inputs must not use local URLs anywhere in flake.nix.
# The optional opening quote (`"?`) catches both quoted local refs
# (`url = "git+file:///..."`) and bare Nix path literals
# (`url = ./foo;`, `path = ./foo;`, attrset form
# `inputs.foo = { type = "path"; path = ./foo; };`). Inventory no-local-url
# checks add per-input flake.lock validation below.
# The second grep drops comment-only matches (line content starting with `#`).
local_url_hits="$tmp_root/local-url-hits.txt"
if grep -nE '(url|path)[[:space:]]*=[[:space:]]*"?((path|git\+file|file):|/|\.\.?/)' flake.nix |
  grep -vE '^[0-9]+:[[:space:]]*#' >"$local_url_hits"; then
  error_msg "flake.nix contains a local input URL"
  sed 's/^/  flake.nix:/' "$local_url_hits" >&2
fi

if [ "$fail" -ne 0 ]; then
  exit "$fail"
fi

nix_eval_flags=()
if [ -n "${CHECK_MAINTAINED_INPUTS_NIX_EVAL_FLAGS:-}" ]; then
  read -r -a nix_eval_flags <<<"$CHECK_MAINTAINED_INPUTS_NIX_EVAL_FLAGS"
fi

inventory_eval_stderr="$tmp_root/inventory-eval.stderr"
inventory_export_failed=0
# --accept-flake-config is required so the flake's nixConfig
# (pipe-operators, allow-import-from-derivation) loads. Without it, import-tree
# fails to parse modules that use pipe-operator syntax and the eval drops into
# the fallback path.
if ! nix eval --accept-flake-config "${nix_eval_flags[@]}" --json '.#lib.meta.maintainedInputs' >"$inventory_json" 2>"$inventory_eval_stderr"; then
  # Keep validating with raw inventory data so lock-source diagnostics are not masked.
  inventory_export_failed=1
  inventory_expr='(import ./modules/meta/maintained-inputs.nix {}).flake.lib.meta.maintainedInputs'
  if ! nix eval --impure --json --expr "$inventory_expr" >"$inventory_json"; then
    echo "maintained-inputs: failed to evaluate .#lib.meta.maintainedInputs" >&2
    sed 's/^/  /' "$inventory_eval_stderr" >&2
    exit 1
  fi
fi

flake_inputs_expr='builtins.attrNames ((import ./flake.nix).inputs or {})'
if ! nix eval --impure --json --expr "$flake_inputs_expr" >"$flake_inputs_json"; then
  echo "maintained-inputs: failed to evaluate flake.nix inputs" >&2
  exit 1
fi

if [ "$(jq 'length' "$inventory_json")" -eq 0 ]; then
  if [ "$inventory_export_failed" -eq 1 ]; then
    error_msg "failed to evaluate .#lib.meta.maintainedInputs"
    sed 's/^/  /' "$inventory_eval_stderr" >&2
  fi
  exit "$fail"
fi

is_local_flake_ref() {
  [[ $1 =~ ^(path:|git\+file:|file:|/|\.\.?/) ]]
}

has_check() {
  local item check
  item="$1"
  check="$2"
  jq -e --arg check "$check" '.checks // [] | index($check)' <<<"$item" >/dev/null
}

valid_check_name() {
  case "$1" in
  clean-checkout | reachable-commit | tracked-files | follows-preserved | lock-graph | no-local-url)
    return 0
    ;;
  *)
    return 1
    ;;
  esac
}

json_string() {
  jq -r "$1 // empty" <<<"$2"
}

while IFS= read -r encoded; do
  record=$(printf '%s' "$encoded" | base64 -d)
  id=$(jq -r '.key' <<<"$record")
  item=$(jq -c '.value' <<<"$record")

  flake_input=$(json_string '.flakeInput' "$item")
  upstream_url=$(json_string '.upstream.url' "$item")
  upstream_ref=$(json_string '.upstream.ref' "$item")
  source_mode=$(json_string '.sourceMode' "$item")
  path_env=$(json_string '.local.pathEnv' "$item")

  [ -n "$flake_input" ] || error_msg "$id: missing flakeInput"
  [ -n "$upstream_url" ] || error_msg "$id: missing upstream.url"
  [ -n "$upstream_ref" ] || error_msg "$id: missing upstream.ref"
  [ -n "$source_mode" ] || error_msg "$id: missing sourceMode"

  case "$source_mode" in
  remote-locked | local-override | submodule)
    ;;
  *)
    error_msg "$id: unknown sourceMode: $source_mode"
    ;;
  esac

  while IFS= read -r check_name; do
    if ! valid_check_name "$check_name"; then
      error_msg "$id: unknown check: $check_name"
    fi
  done < <(jq -r '.checks[]?' <<<"$item")

  if [ -z "$flake_input" ]; then
    continue
  fi

  if ! jq -e --arg input "$flake_input" 'index($input)' "$flake_inputs_json" >/dev/null; then
    error_msg "$id: flake input $flake_input is not in flake.nix inputs"
    continue
  fi

  node=$(jq -r --arg input "$flake_input" '.nodes.root.inputs[$input] // empty' flake.lock)
  if [ -z "$node" ]; then
    error_msg "$id: flake input $flake_input is not in flake.lock root inputs"
    continue
  fi

  if has_check "$item" no-local-url; then
    for section in locked original; do
      input_type=$(jq -r --arg node "$node" --arg section "$section" '.nodes[$node][$section].type // empty' flake.lock)
      input_url=$(jq -r --arg node "$node" --arg section "$section" '.nodes[$node][$section].url // empty' flake.lock)
      input_path=$(jq -r --arg node "$node" --arg section "$section" '.nodes[$node][$section].path // empty' flake.lock)
      if [ "$input_type" = "path" ] || [ -n "$input_path" ] || is_local_flake_ref "$input_url"; then
        error_msg "$id: flake.lock $section source for $flake_input is a local path"
      fi
    done
  fi

  if has_check "$item" follows-preserved; then
    expected_follows=$(jq -c '.follows // {}' <<<"$item")
    if [ "$expected_follows" = "{}" ]; then
      error_msg "$id: follows-preserved check declared but follows is empty or missing"
    fi
    while IFS= read -r follow_record; do
      follow_name=$(jq -r '.key' <<<"$follow_record")
      expected=$(jq -r '.value' <<<"$follow_record")
      expected_json=$(jq -cn --arg expected "$expected" '$expected | split("/")')
      actual_json=$(jq -c --arg node "$node" --arg follow "$follow_name" '.nodes[$node].inputs[$follow] // null' flake.lock)
      if [ "$actual_json" != "$expected_json" ]; then
        error_msg "$id: follows.$follow_name expected $expected_json but flake.lock has $actual_json"
      fi
    done < <(jq -c '.follows // {} | to_entries[]' <<<"$item")
  fi

  if has_check "$item" lock-graph; then
    expected_inputs=$(jq -c '.lockGraph.inputNames // [] | sort' <<<"$item")
    if [ "$expected_inputs" = "[]" ]; then
      error_msg "$id: lock-graph check declared but lockGraph.inputNames is empty or missing"
    else
      actual_inputs=$(jq -c --arg node "$node" '.nodes[$node].inputs // {} | keys | sort' flake.lock)
      if [ "$actual_inputs" != "$expected_inputs" ]; then
        error_msg "$id: lock graph input names expected $expected_inputs but flake.lock has $actual_inputs"
      fi
    fi
  fi

  if { has_check "$item" clean-checkout || has_check "$item" tracked-files; } && [ -z "$path_env" ]; then
    error_msg "$id: clean-checkout or tracked-files declared but local.pathEnv is missing"
  fi

  if [ -n "$path_env" ]; then
    checkout="${!path_env:-}"
    if [ -n "$checkout" ]; then
      if ! git -C "$checkout" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        error_msg "$id: $path_env does not point at a git checkout: $checkout"
      else
        status=$(git -C "$checkout" status --porcelain=v1 --untracked-files=all)
        if [ -n "$status" ] && has_check "$item" clean-checkout; then
          error_msg "$id: checkout from $path_env is dirty or has untracked files"
          printf -- '%s\n' "$status" | sed "s/^/  $id: /" >&2
        fi
        if [ -n "$status" ] && has_check "$item" tracked-files && grep -q '^?? ' <<<"$status"; then
          error_msg "$id: checkout from $path_env has untracked files"
          printf -- '%s\n' "$status" | sed "s/^/  $id: /" >&2
        fi
      fi
    fi
  fi

  if [ "$fetch" -eq 1 ] && has_check "$item" reachable-commit; then
    locked_rev=$(jq -r --arg node "$node" '.nodes[$node].locked.rev // empty' flake.lock)
    if [ -z "$locked_rev" ]; then
      error_msg "$id: flake.lock has no locked rev for $flake_input"
    else
      remote_check_dir=$(mktemp -d "$tmp_root/$id.reachability.XXXXXX")
      git -C "$remote_check_dir" init --quiet
      git -C "$remote_check_dir" remote add origin "$upstream_url"
      if git -C "$remote_check_dir" fetch --filter=blob:none --quiet origin "$upstream_ref"; then
        if ! git -C "$remote_check_dir" merge-base --is-ancestor "$locked_rev" FETCH_HEAD; then
          error_msg "$id: locked rev $locked_rev is not reachable from $upstream_url $upstream_ref"
        fi
      else
        error_msg "$id: failed to fetch $upstream_url $upstream_ref"
      fi
    fi
  fi
done < <(jq -r 'to_entries[] | @base64' "$inventory_json")

if [ "$inventory_export_failed" -eq 1 ]; then
  error_msg "failed to evaluate .#lib.meta.maintainedInputs"
  sed 's/^/  /' "$inventory_eval_stderr" >&2
fi

exit "$fail"
