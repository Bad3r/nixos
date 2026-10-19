#!/usr/bin/env bash
set -euo pipefail

uv run --offline --no-project --no-managed-python --python python3.14 tests/windows-guest-filesystem/test_provision.py
