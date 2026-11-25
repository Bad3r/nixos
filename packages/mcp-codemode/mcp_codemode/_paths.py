# Copyright (c) 2026 Bad3r

"""Build-time runtime paths substituted by Nix, with PATH/dev fallbacks."""

from __future__ import annotations

import shutil
from pathlib import Path

BAKED_NODE_BIN = "@node@"
BAKED_BWRAP_BIN = "@bwrap@"
BAKED_SANDBOX_SCRIPT = "@sandbox@"


def resolve_node_bin() -> str:
    """Return the Node 24 executable path."""
    if not BAKED_NODE_BIN.startswith("@"):
        return BAKED_NODE_BIN
    return shutil.which("node") or "node"


def resolve_bwrap_bin() -> str | None:
    """Return the Bubblewrap executable path, or None if unavailable in dev."""
    if not BAKED_BWRAP_BIN.startswith("@"):
        return BAKED_BWRAP_BIN
    return shutil.which("bwrap")


def resolve_sandbox_script() -> Path:
    """Return the path to sandbox.mjs."""
    if not BAKED_SANDBOX_SCRIPT.startswith("@"):
        return Path(BAKED_SANDBOX_SCRIPT)
    return Path(__file__).resolve().parent.parent / "sandbox.mjs"
