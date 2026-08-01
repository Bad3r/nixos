#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

shopt -s nullglob
updaters=(packages/*/update.py)
shopt -u nullglob

total=${#updaters[@]}

if [ "$total" -eq 0 ]; then
  printf 'No package updaters found.\n'
  exit 0
fi

index=0

printf 'Package updaters: %s\n' "$total"

for updater in "${updaters[@]}"; do
  index=$((index + 1))

  printf '\n[%s/%s] %s\n' "$index" "$total" "$updater"

  if "$updater"; then
    printf '[%s/%s] done: %s\n' "$index" "$total" "$updater"
  else
    status=$?
    printf '[%s/%s] failed with exit code %s: %s\n' "$index" "$total" "$status" "$updater" >&2
    exit "$status"
  fi
done
