#!/usr/bin/env nix
#! nix shell nixpkgs#dash --command dash
# shellcheck shell=dash

set -eu

total=0

for updater in packages/*/update.py; do
  [ -f "$updater" ] || continue
  total=$((total + 1))
done

if [ "$total" -eq 0 ]; then
  printf 'No package updaters found.\n'
  exit 0
fi

index=0

printf 'Package updaters: %s\n' "$total"

for updater in packages/*/update.py; do
  [ -f "$updater" ] || continue
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
