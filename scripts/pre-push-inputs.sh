#!/usr/bin/env bash
set -euo pipefail

# Push vendored inputs/* submodules to the superproject origin using a standard branch name:
#   inputs/<superproject-branch>/<input-name>
#
# Usage:
#   scripts/pre-push-inputs.sh [--dry-run]
#
# Notes:
# - Only pushes inputs that are actual Git repos under inputs/*.
# - Requires that the superproject has an 'origin' remote.
# - If installed as .git/hooks/pre-push, it will run on every push from the superproject.

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "$ROOT" || ! -d "$ROOT/.git" ]]; then
  echo "Error: must run inside the superproject git repository" >&2
  exit 1
fi
cd "$ROOT"

if ! git remote get-url origin >/dev/null 2>&1; then
  echo "Error: superproject has no 'origin' remote" >&2
  exit 1
fi

SP_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)
echo "Superproject branch: $SP_BRANCH"

shopt -s nullglob
inputs=(inputs/*)
shopt -u nullglob

if [[ ${#inputs[@]} -eq 0 ]]; then
  echo "No inputs/* found; nothing to push."
  exit 0
fi

for d in "${inputs[@]}"; do
  [[ -d "$d" ]] || continue
  # Treat both submodule worktrees and regular git repos
  if git -C "$d" rev-parse --git-dir >/dev/null 2>&1; then
    name=$(basename "$d")
    target="inputs/$SP_BRANCH/$name"
    echo "==> $name: pushing HEAD -> origin:$target"
    if [[ $DRY_RUN -eq 1 ]]; then
      printf "(dry-run) git -C '%s' push --force-with-lease -u origin HEAD:refs/heads/%s\n" "$d" "$target"
    else
      git -C "$d" push --force-with-lease -u origin "HEAD:refs/heads/$target"
    fi
  fi
done

echo "Done."
