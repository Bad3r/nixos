#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "${script_dir}/test_update.py" "${1:-${script_dir}/../..}"
