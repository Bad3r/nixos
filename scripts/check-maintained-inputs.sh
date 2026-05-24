#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

# Git sets GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE when invoking hooks,
# and subprocess git inherits them. Without unsetting, `git -C inputs/<name>`
# still operates on the parent repo's GIT_DIR and silently ignores `-C`,
# which makes submodule status checks report parent-repo paths as deleted.
# Discovery from CWD reproduces the correct worktree for both hook and
# direct invocations.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

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

is_local_flake_ref() {
  [[ $1 =~ ^(path:|git\+file:|file:|/|\.\.?/) ]]
}

# Best-effort pre-check on flake.nix; the lock-based scan below is the
# authoritative policy. The leading `[^[:alnum:]_]` anchors `(url|path)` to a
# non-identifier boundary so unrelated identifiers like `my_path` or
# `local_url` cannot substring-match (the awk `N:` prefix guarantees a
# preceding char even at column 0). The optional opening quote (`"?`) catches
# both quoted local refs (`url = "git+file:///..."`) and bare Nix path
# literals (`url = ./foo;`, `path = ./foo;`, attrset form
# `inputs.foo = { type = "path"; path = ./foo; };`). awk strips end-of-line
# comments (`<whitespace>#...`) so a trailing comment that mentions a local
# URL (`url = "github:foo"; # was path = ./local`) does not produce a false
# positive that would block the push before the authoritative lock scan
# runs. The follow-up grep still drops any whole-line `#` comment that
# starts at column 0. Block comments (`/* ... */`) are not handled. Paths
# beginning with `"./inputs/` are the project's submodule-backed local-input
# convention (see `modules/meta/maintained-inputs.nix`, sourceMode =
# "submodule") and are excluded here; the per-input loop below verifies that
# every such path is registered in the maintained inventory and resolves to
# the expected `inputs/<flakeInput>` directory.
local_url_hits="$tmp_root/local-url-hits.txt"
if awk '{sub(/[[:space:]]+#.*$/, ""); print NR":" $0}' flake.nix |
  grep -E '[^[:alnum:]_](url|path)[[:space:]]*=[[:space:]]*"?((path|git\+file|file):|/|\.\.?/)' |
  grep -vE '^[0-9]+:[[:space:]]*#' |
  grep -vE '[^[:alnum:]_](url|path)[[:space:]]*=[[:space:]]*"\.?/inputs/' >"$local_url_hits"; then
  error_msg "flake.nix contains a local input URL"
  sed 's/^/  flake.nix:/' "$local_url_hits" >&2
fi

if [ "$fail" -ne 0 ]; then
  exit "$fail"
fi

inventory_eval_stderr="$tmp_root/inventory-eval.stderr"
# Read the inventory by importing the module file directly rather than via
# `nix eval .#lib.meta.maintainedInputs`. The flake-output path forces a
# full flake evaluation, which copies every input source (including
# submodule-backed inputs/<flakeInput> trees, multi-GB for nixpkgs) into the
# Nix store and triggers nix's git fetcher to populate its own gitv3 cache
# for any input URL it hasn't seen. That made the pre-push hook take 30+
# minutes on a first run. The inventory file is pure static data with no
# input references, so `(import ./modules/meta/maintained-inputs.nix {})`
# returns the same attrset in milliseconds and stays offline.
inventory_expr='(import ./modules/meta/maintained-inputs.nix {}).flake.lib.meta.maintainedInputs'
if ! nix eval --impure --json --expr "$inventory_expr" >"$inventory_json" 2>"$inventory_eval_stderr"; then
  echo "maintained-inputs: failed to import modules/meta/maintained-inputs.nix" >&2
  sed 's/^/  /' "$inventory_eval_stderr" >&2
  exit 1
fi

flake_inputs_expr='builtins.attrNames ((import ./flake.nix).inputs or {})'
if ! nix eval --impure --json --expr "$flake_inputs_expr" >"$flake_inputs_json"; then
  echo "maintained-inputs: failed to evaluate flake.nix inputs" >&2
  exit 1
fi

# Authoritative repo-wide policy for non-inventory root inputs: every flake
# input not declared in the inventory must resolve to a non-local source in
# flake.lock. flake.lock normalizes every input to JSON, so this iteration is
# immune to formatting issues that affect the line-based flake.nix grep
# above (nixfmt-wrapped values, inline trailing comments). Inventory-declared
# inputs run the same scan unconditionally inside the per-input loop below;
# the explicit `allowLocalSource = true` opt-out covers offline
# reachable-commit fixtures that legitimately use `file://` upstream URLs.
# Single jq pass: emits `name<TAB>section` for each offending entry. Skips
# root-level follows arrays (`select((.value | type) == "string")`) and
# inventory-declared inputs via the slurped exemption set.
inventory_flake_inputs_json="$tmp_root/inventory-flake-inputs.json"
jq '[.[] | .flakeInput // empty]' "$inventory_json" >"$inventory_flake_inputs_json"
while IFS=$'\t' read -r root_input section; do
  error_msg "flake.lock $section source for $root_input is a local path"
done < <(jq -r --slurpfile inv "$inventory_flake_inputs_json" '
  ($inv[0] // []) as $exempt
  | . as $root
  | $root.nodes.root.inputs
  | to_entries[]
  | select((.value | type) == "string")
  | .key as $name
  | .value as $node_name
  | select(($exempt | index($name)) | not)
  | $root.nodes[$node_name] as $node
  | ("locked", "original") as $section
  | ($node[$section] // {})
  | select((.type == "path") or ((.path // "") != "") or ((.url // "") | test("^(path:|git\\+file:|file:|/|\\.\\.?/)")))
  | "\($name)\t\($section)"
' flake.lock)

if [ "$(jq 'length' "$inventory_json")" -eq 0 ]; then
  exit "$fail"
fi

has_check() {
  local item check
  item="$1"
  check="$2"
  jq -e --arg check "$check" '.checks // [] | index($check)' <<<"$item" >/dev/null
}

valid_check_name() {
  case "$1" in
  clean-checkout | reachable-commit | tracked-files | follows-preserved | lock-graph | upstream-fresh)
    return 0
    ;;
  *)
    return 1
    ;;
  esac
}

# Maximum age, in days, accepted by the upstream-fresh check. Configurable via
# the MAINTAINED_INPUTS_FRESHNESS_DAYS env var so CI jobs can tighten or
# loosen the gate without editing the script.
freshness_days="${MAINTAINED_INPUTS_FRESHNESS_DAYS:-14}"

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
  allow_local_source=$(jq -r '.allowLocalSource // false' <<<"$item")

  [ -n "$flake_input" ] || error_msg "$id: missing flakeInput"
  [ -n "$upstream_url" ] || error_msg "$id: missing upstream.url"
  [ -n "$upstream_ref" ] || error_msg "$id: missing upstream.ref"
  [ -n "$source_mode" ] || error_msg "$id: missing sourceMode"

  # forkOf is optional, but when present must carry both url and ref so
  # the docs/tooling layer can render unambiguous "fork of <url> @ <ref>"
  # statements without falling back to upstream.* values.
  if jq -e 'has("forkOf")' <<<"$item" >/dev/null; then
    fork_of_url=$(json_string '.forkOf.url' "$item")
    fork_of_ref=$(json_string '.forkOf.ref' "$item")
    [ -n "$fork_of_url" ] || error_msg "$id: forkOf is set but forkOf.url is missing"
    [ -n "$fork_of_ref" ] || error_msg "$id: forkOf is set but forkOf.ref is missing"
  fi

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

  # Local-source policy:
  #   - sourceMode = "submodule": the lock is expected to be type = "path"
  #     with path = "./inputs/<flakeInput>"; mismatch is the error.
  #   - sourceMode in {"remote-locked","local-override"} with
  #     allowLocalSource = true: the entry legitimately points at a local
  #     ref (offline reachable-commit fixtures); skip the scan.
  #   - otherwise: reject any local-path lock metadata.
  case "$source_mode" in
  submodule)
    expected_path="./inputs/$flake_input"
    for section in locked original; do
      input_path=$(jq -r --arg node "$node" --arg section "$section" '.nodes[$node][$section].path // empty' flake.lock)
      if [ "$input_path" != "$expected_path" ]; then
        error_msg "$id: flake.lock $section.path for $flake_input expected $expected_path but got '$input_path'"
      fi
    done
    # Enforce the documented invariant that upstream.url for sourceMode =
    # "submodule" matches the URL recorded in .gitmodules for inputs/<name>.
    # If the two drift, `reachable-commit --fetch` queries a remote that fresh
    # `git clone --recurse-submodules` never uses: a gitlink commit reachable
    # from upstream.url but absent from the .gitmodules remote would pass the
    # fetch check yet break fresh clones. The .gitmodules section name can
    # differ from the path (e.g. `submodule "stylix"` for `path = inputs/stylix`),
    # so the section name is recovered by matching the .path field. The
    # existence guard keeps the lookup quiet when .gitmodules is absent
    # entirely (fail-submodule-missing test path); the directory-missing check
    # later in this loop is the diagnostic that drives the operator to
    # initialize the submodule.
    if [ -f .gitmodules ]; then
      gitmodules_name=$(git config -f .gitmodules --get-regexp '\.path$' 2>/dev/null |
        awk -v p="inputs/$flake_input" '$2 == p { name = $1; sub(/^submodule\./, "", name); sub(/\.path$/, "", name); print name; exit }')
      if [ -n "$gitmodules_name" ]; then
        gitmodules_url=$(git config -f .gitmodules --get "submodule.$gitmodules_name.url" || true)
        if [ -n "$gitmodules_url" ] && [ "$gitmodules_url" != "$upstream_url" ]; then
          error_msg "$id: upstream.url '$upstream_url' does not match .gitmodules url '$gitmodules_url' for inputs/$flake_input"
        fi
      fi
    fi
    ;;
  *)
    if [ "$allow_local_source" != "true" ]; then
      for section in locked original; do
        input_type=$(jq -r --arg node "$node" --arg section "$section" '.nodes[$node][$section].type // empty' flake.lock)
        input_url=$(jq -r --arg node "$node" --arg section "$section" '.nodes[$node][$section].url // empty' flake.lock)
        input_path=$(jq -r --arg node "$node" --arg section "$section" '.nodes[$node][$section].path // empty' flake.lock)
        if [ "$input_type" = "path" ] || [ -n "$input_path" ] || is_local_flake_ref "$input_url"; then
          error_msg "$id: flake.lock $section source for $flake_input is a local path"
        fi
      done
    fi
    ;;
  esac

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

  # Checkout resolution depends on sourceMode:
  #   - submodule: derived from the convention inputs/<flakeInput>; the
  #     checkout must exist (submodule initialized) for any clean-checkout
  #     or tracked-files claim to be enforceable.
  #   - non-submodule: optional $pathEnv-named env var points at the
  #     external checkout; an empty env var skips the checks (off-host
  #     workflows).
  checkout=""
  if [ "$source_mode" = "submodule" ]; then
    checkout="inputs/$flake_input"
  elif [ -n "$path_env" ]; then
    checkout="${!path_env:-}"
  fi

  if { has_check "$item" clean-checkout || has_check "$item" tracked-files; } &&
    [ "$source_mode" != "submodule" ] && [ -z "$path_env" ]; then
    error_msg "$id: clean-checkout or tracked-files declared but local.pathEnv is missing"
  fi

  if [ -n "$checkout" ]; then
    if [ "$source_mode" = "submodule" ]; then
      # Submodule mode resolution is split into three states:
      #   1. Directory missing entirely: the gitlink was never materialized
      #      (no submodule update). Error out so operators initialize it.
      #   2. Directory present but no submodule worktree at this path:
      #      pre-commit's pre-push checkout creates empty placeholders for
      #      gitlinks without recursing submodules, so a plain
      #      `git -C $checkout` would walk up and discover the parent's
      #      .git. The lock-path and reachable-commit checks above already
      #      validate the gitlink itself, so worktree-level checks are
      #      skipped here.
      #   3. Submodule worktree present: run worktree-level checks
      #      against the submodule.
      # `git rev-parse --show-superproject-working-tree` returns the parent
      # worktree path only when the current repo is actually a submodule,
      # which differentiates (2) from (3) without false positives from
      # git's upward auto-discovery.
      if [ ! -d "$checkout" ]; then
        error_msg "$id: submodule directory missing at $checkout; run 'git submodule update --init --recursive'"
      else
        superproject=$(git -C "$checkout" rev-parse --show-superproject-working-tree 2>/dev/null || true)
        if [ -n "$superproject" ]; then
          status=$(git -C "$checkout" status --porcelain=v1 --untracked-files=all)
          if [ -n "$status" ] && has_check "$item" clean-checkout; then
            error_msg "$id: checkout at $checkout is dirty or has untracked files"
            printf -- '%s\n' "$status" | sed "s/^/  $id: /" >&2
          fi
          if [ -n "$status" ] && has_check "$item" tracked-files && grep -q '^?? ' <<<"$status"; then
            error_msg "$id: checkout at $checkout has untracked files"
            printf -- '%s\n' "$status" | sed "s/^/  $id: /" >&2
          fi
        fi
      fi
    elif ! git -C "$checkout" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      error_msg "$id: $path_env does not point at a git checkout: $checkout"
    else
      status=$(git -C "$checkout" status --porcelain=v1 --untracked-files=all)
      if [ -n "$status" ] && has_check "$item" clean-checkout; then
        error_msg "$id: checkout at $checkout is dirty or has untracked files"
        printf -- '%s\n' "$status" | sed "s/^/  $id: /" >&2
      fi
      if [ -n "$status" ] && has_check "$item" tracked-files && grep -q '^?? ' <<<"$status"; then
        error_msg "$id: checkout at $checkout has untracked files"
        printf -- '%s\n' "$status" | sed "s/^/  $id: /" >&2
      fi
    fi
  fi

  if [ "$fetch" -eq 1 ] && has_check "$item" reachable-commit; then
    # Submodule mode: locked rev is the gitlink commit in the parent tree,
    # since path-type lock entries carry no rev. Other modes: locked rev is
    # the flake.lock locked.rev field.
    locked_rev=""
    if [ "$source_mode" = "submodule" ]; then
      # Read the gitlink from the index so staged-but-not-committed adds
      # still validate. The index reflects HEAD plus staged changes, which
      # matches both pre-commit and pre-push semantics.
      locked_rev=$(git ls-files -s "inputs/$flake_input" | awk '{print $2}')
      if [ -z "$locked_rev" ]; then
        error_msg "$id: no submodule gitlink recorded at inputs/$flake_input"
      fi
    else
      locked_rev=$(jq -r --arg node "$node" '.nodes[$node].locked.rev // empty' flake.lock)
      if [ -z "$locked_rev" ]; then
        error_msg "$id: flake.lock has no locked rev for $flake_input"
      fi
    fi
    if [ -n "$locked_rev" ]; then
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

  # upstream-fresh: validate that the gitlinked SHA is also reachable from the
  # canonical upstream (forkOf.ref) AND that the commit timestamp is within
  # the freshness window. Replaces flake-checker's NixOS-owner / supported-ref
  # / numDaysOld semantics, with the difference that we check the gitlink
  # against the canonical-source-of-record rather than the fork's own ref.
  # The check is meaningful only when forkOf is set; for inventory entries
  # without a canonical upstream there is no second remote to compare to.
  if [ "$fetch" -eq 1 ] && has_check "$item" upstream-fresh; then
    fork_of_url=$(json_string '.forkOf.url' "$item")
    fork_of_ref=$(json_string '.forkOf.ref' "$item")
    [ -n "$fork_of_url" ] || error_msg "$id: upstream-fresh declared but forkOf.url is missing"
    [ -n "$fork_of_ref" ] || error_msg "$id: upstream-fresh declared but forkOf.ref is missing"
    fresh_rev=""
    if [ "$source_mode" = "submodule" ]; then
      fresh_rev=$(git ls-files -s "inputs/$flake_input" | awk '{print $2}')
    else
      fresh_rev=$(jq -r --arg node "$node" '.nodes[$node].locked.rev // empty' flake.lock)
    fi
    if [ -n "$fork_of_url" ] && [ -n "$fork_of_ref" ] && [ -n "$fresh_rev" ]; then
      canonical_dir=$(mktemp -d "$tmp_root/$id.upstream-fresh.XXXXXX")
      git -C "$canonical_dir" init --quiet
      git -C "$canonical_dir" remote add canonical "$fork_of_url"
      if git -C "$canonical_dir" fetch --filter=blob:none --quiet canonical "$fork_of_ref"; then
        if ! git -C "$canonical_dir" merge-base --is-ancestor "$fresh_rev" FETCH_HEAD; then
          error_msg "$id: locked rev $fresh_rev is not reachable from canonical $fork_of_url $fork_of_ref"
        fi
        # Commit timestamp lookup. For submodule mode the gitlinked commit is
        # in the submodule checkout; for other modes it is in the canonical
        # clone (we fetched it). Either way the SHA resolves through the
        # canonical clone because we filter by blob and need only the tree
        # metadata.
        commit_ts=$(git -C "$canonical_dir" log -1 --format=%ct "$fresh_rev" 2>/dev/null || true)
        if [ -n "$commit_ts" ]; then
          now_ts=$(date +%s)
          age_seconds=$((now_ts - commit_ts))
          max_age_seconds=$((freshness_days * 86400))
          if [ "$age_seconds" -gt "$max_age_seconds" ]; then
            age_days=$((age_seconds / 86400))
            error_msg "$id: locked rev $fresh_rev is $age_days days old; freshness threshold is $freshness_days days"
          fi
        else
          error_msg "$id: failed to resolve commit timestamp for $fresh_rev in canonical $fork_of_url"
        fi
      else
        error_msg "$id: failed to fetch canonical $fork_of_url $fork_of_ref"
      fi
    fi
  fi
done < <(jq -r 'to_entries[] | @base64' "$inventory_json")

exit "$fail"
