# Copyright (c) 2026 Bad3r

"""Write a dynamically patched copy of the `agy` CLI binary.

Usage: python3 -I _patch_agy.py IN OUT [--patches SET[,SET...]] [--version VER]

Patch sets (all discovered dynamically at build time):
  notelemetry   Forces `language_server.Options.DisableTelemetry = true` at entry to
                `CreateLanguageServerAndServe` (field offset recovered from Go RTTI) and sets
                `main`'s package-level `Options.DisableTelemetry = true` at `main.main` entry.
  noautoupdate  Forces `updater.triggerUpdateShared` to jump to its `"Auto-update disabled via
                environment variable"` return.
  quietwatcher  NOPs the `log.ctxlogf` call for `"skipping empty or temp file: %s"` inside
                `(*FileWatcherDefault).listenAndForwardEvents`.
"""

from __future__ import annotations

import sys
from pathlib import Path

_ROOT = str(Path(__file__).resolve().parent)
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)

from _agy_patcher.cli import main  # noqa: E402
from _agy_patcher.patches import PATCH_SETS  # noqa: E402

__all__ = ["PATCH_SETS", "main"]

if __name__ == "__main__":
    main(sys.argv[1:])
