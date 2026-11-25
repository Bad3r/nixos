# Copyright (c) 2026 Bad3r

"""Shared protocol constants, JSON coercers, timeout checks, and process cleanup."""

from __future__ import annotations

import math
import os
import signal
import subprocess
from typing import TypeGuard, cast

from . import __version__

PROTOCOL_VERSION = "2025-03-26"
SUPPORTED_PROTOCOL_VERSIONS = frozenset({"2024-11-05", "2025-03-26", "2025-06-18"})
PACKAGE_INFO = {"name": "mcp-codemode", "version": __version__}
RPC_METHOD_NOT_FOUND = -32601


def as_dict(value: object) -> dict[str, object] | None:
    """Return a shallow string-keyed copy if value is a dict, else None."""
    if not isinstance(value, dict):
        return None
    raw = cast("dict[object, object]", value)
    return {str(k): v for k, v in raw.items()}


def as_list(value: object) -> list[object] | None:
    """Return a shallow copy if value is a list, else None."""
    if not isinstance(value, list):
        return None
    return list(cast("list[object]", value))


def as_dict_list(value: object) -> list[dict[str, object]]:
    """Return all dict items inside a JSON list value."""
    items = as_list(value)
    if items is None:
        return []
    out: list[dict[str, object]] = []
    for item in items:
        item_dict = as_dict(item)
        if item_dict is not None:
            out.append(item_dict)
    return out


def is_valid_rpc_id(value: object) -> TypeGuard[str | int | float]:
    """Return True when value is a hashable JSON-RPC 2.0 request ID (string or finite number)."""
    if isinstance(value, bool):
        return False
    if isinstance(value, (str, int)):
        return True
    return isinstance(value, float) and math.isfinite(value)


def parse_positive_timeout(value: object) -> float | None:
    """Return a positive finite float timeout, or None when invalid."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    result = float(value)
    if not math.isfinite(result) or result <= 0:
        return None
    return result


def terminate_process_group(proc: subprocess.Popen[str], grace_sec: float) -> None:
    """Send SIGTERM to a child's process group, escalating to SIGKILL after grace_sec."""
    if proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except OSError:
        proc.terminate()
    try:
        proc.wait(timeout=grace_sec)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            proc.kill()
        proc.wait()
