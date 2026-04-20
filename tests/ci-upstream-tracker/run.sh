#!/usr/bin/env bash
# shellcheck shell=bash
# Fixture-driven tests for upstream-tracker.sh.
# Uses UPSTREAM_TRACKER_OFFLINE_MOCKS so no live API calls fire.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/../../.github/scripts/upstream-tracker.sh"
FAKE_NOW="2026-04-20T18:17Z"

if [[ ! -x $SUT ]]; then
  printf 'run.sh: SUT not executable at %s\n' "$SUT" >&2
  exit 2
fi

pass=0
fail=0
failures=()

shopt -s nullglob
for fixture in "$SCRIPT_DIR/fixtures"/*.md; do
  name="$(basename "$fixture" .md)"
  expected="$SCRIPT_DIR/golden/$name.json"
  mocks_dir="$SCRIPT_DIR/api-mocks/$name"
  [[ -d $mocks_dir ]] || mocks_dir="$SCRIPT_DIR/api-mocks/_empty"

  if [[ ! -f $expected ]]; then
    printf 'FAIL: %s — missing golden %s\n' "$name" "$expected" >&2
    failures+=("$name")
    fail=$((fail + 1))
    continue
  fi

  stderr_file="$(mktemp)"
  actual_raw="$(UPSTREAM_TRACKER_FAKE_NOW="$FAKE_NOW" \
    UPSTREAM_TRACKER_OFFLINE_MOCKS="$mocks_dir" \
    UPSTREAM_TRACKER_PARSE_ONLY=1 \
    "$SUT" <"$fixture" 2>"$stderr_file")"

  diff_out="$(diff -u \
    <(printf '%s' "$actual_raw" | jq -S .) \
    <(jq -S . "$expected") || true)"

  if [[ -n $diff_out ]]; then
    printf 'FAIL: %s\n' "$name" >&2
    printf '%s\n' "$diff_out" >&2
    if [[ -s $stderr_file ]]; then
      printf '  script stderr:\n' >&2
      sed 's/^/    /' "$stderr_file" >&2
    fi
    failures+=("$name")
    fail=$((fail + 1))
  else
    pass=$((pass + 1))
  fi
  rm -f "$stderr_file"
done

printf '%d passed, %d failed\n' "$pass" "$fail"
if ((fail > 0)); then
  printf 'failed fixtures: %s\n' "${failures[*]}"
  exit 1
fi
