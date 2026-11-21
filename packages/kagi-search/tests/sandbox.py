# Copyright (c) 2026 Bad3r
"""Whether this host can run the PDF renderer's sandbox, for the tests that need it."""

from __future__ import annotations

import functools
import subprocess
import sys
import unittest

from kagi_search import pdf


@functools.cache
def unavailable() -> str | None:
    """Why bubblewrap cannot confine a child here, or None when it can.

    A host that refuses user namespaces (a build sandbox without them, AppArmor's
    restriction of unprivileged ones) is named rather than failed.
    """
    if pdf.BWRAP.startswith("@"):
        return "the source tree's bubblewrap is not a store path; run against the installed package"
    probe = [pdf.BWRAP, "--unshare-all", "--ro-bind", pdf.STORE, pdf.STORE, "--"]
    try:
        ran = subprocess.run(
            [*probe, sys.executable, "-IB", "-c", "pass"],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return f"bubblewrap cannot run: {error}"
    if ran.returncode == 0:
        return None
    tail = ran.stderr.strip().splitlines()[-1:] or [f"exit {ran.returncode}"]
    return f"bubblewrap cannot confine a child here: {tail[0][:300]}"


def require() -> None:
    """Skip the calling test class, saying why on stderr, when the sandbox cannot start."""
    reason = unavailable()
    if reason is not None:
        print(f"\nskipping PDF renderer tests: {reason}", file=sys.stderr, flush=True)
        raise unittest.SkipTest(reason)
