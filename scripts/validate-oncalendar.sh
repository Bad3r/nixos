#!/usr/bin/env bash
set -euo pipefail

if ! command -v systemd-analyze >/dev/null 2>&1; then
  echo "systemd-analyze not found" >&2
  exit 127
fi

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <OnCalendar> [<OnCalendar> ...]" >&2
  exit 64
fi

status=0
for expr in "$@"; do
  if ! systemd-analyze calendar "$expr" >/dev/null 2>&1; then
    echo "Invalid OnCalendar expression: $expr" >&2
    status=1
  fi
done

exit "$status"
