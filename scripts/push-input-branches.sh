#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Push input branches (inputs/*) to the repository origin.

Usage:
  push-input-branches.sh [--debug] [<input> ...]

Options:
  --debug        Enable verbose logging (set -x) and extra diagnostics
  -h, --help     Show this help

Arguments:
  <input>        Optional list of inputs to push (e.g., nixpkgs home-manager stylix).
                 If omitted, auto-discovers inputs under inputs/*.

Behavior:
  - Ensures each submodule's push URL points to the superproject's origin
  - Pushes HEAD of each input to its current branch (e.g., inputs/main/<name>)
  - Uses --force-with-lease and sets upstream on first push
  - Verifies presence of the branch on origin
EOF
}

DEBUG=0
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      DEBUG=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    --)
      shift; break ;;
    -*)
      echo "Unknown option: $1" >&2; usage; exit 2 ;;
    *)
      ARGS+=("$1"); shift ;;
  esac
done

if [[ ${DEBUG} -eq 1 ]]; then
  set -x
fi

# Ensure we are in a git repo and move to its root
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "$ROOT" || ! -d "$ROOT/.git" ]]; then
  echo "Error: run this inside the superproject git repository" >&2
  exit 1
fi
cd "$ROOT"

# Resolve origin URL for push
PARENT_ORIGIN=$(git remote get-url --push origin 2>/dev/null || git remote get-url origin 2>/dev/null || true)
if [[ -z "$PARENT_ORIGIN" ]]; then
  echo "Error: could not resolve superproject origin push URL" >&2
  exit 1
fi

# Build target list
declare -a TARGETS=()
if [[ ${#ARGS[@]} -gt 0 ]]; then
  for name in "${ARGS[@]}"; do
    path="inputs/$name"
    if [[ -d "$path/.git" || -f "$path/.git" ]]; then
      TARGETS+=("$name")
    else
      echo "Warning: skipped '$name' (no git repo at $path)" >&2
    fi
  done
else
  shopt -s nullglob
  for d in inputs/*; do
    [[ -d "$d" ]] || continue
    if [[ -d "$d/.git" || -f "$d/.git" ]]; then
      TARGETS+=("$(basename "$d")")
    fi
  done
  shopt -u nullglob
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "Error: no input submodules found under inputs/*" >&2
  exit 1
fi

echo "Superproject origin (push): $PARENT_ORIGIN"

for name in "${TARGETS[@]}"; do
  path="inputs/$name"
  echo "==> Processing $name ($path)"

  # Ensure remote 'origin' exists in submodule
  if ! git -C "$path" remote get-url origin >/dev/null 2>&1; then
    git -C "$path" remote add origin "$PARENT_ORIGIN"
  fi
  # Set push URL to superproject origin explicitly (keep fetch as ./.)
  git -C "$path" remote set-url --push origin "$PARENT_ORIGIN"

  # Determine branch to push
  branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
    # Fallback to .gitmodules branch config, else derive from superproject branch
    gm_branch=$(git config -f .gitmodules "submodule.$path.branch" 2>/dev/null || echo "")
    if [[ -n "$gm_branch" ]]; then
      branch="$gm_branch"
      echo "Info: detached HEAD; using .gitmodules branch '$branch'"
    else
      sp_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)
      branch="inputs/$sp_branch/$name"
      echo "Info: detached HEAD; defaulting to '$branch'"
    fi
  fi

  echo "Pushing HEAD -> origin:$branch"
  git -C "$path" push --force-with-lease -u origin "HEAD:refs/heads/$branch"

  # Verify on origin
  if git ls-remote --heads "$PARENT_ORIGIN" "$branch" | grep -qE "\srefs/heads/$branch$"; then
    echo "OK: origin has branch '$branch' for $name"
  else
    echo "Warning: could not verify branch '$branch' on origin for $name" >&2
  fi
done

echo "All requested input branches have been pushed."

