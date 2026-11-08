# Copyright (c) 2026 Bad3r
"""What the namespace tests need: a stand-in pasta, and a probe of the host's support."""

from __future__ import annotations

import functools
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from browser_fetch import browser, tools

ROOT = str(Path(__file__).resolve().parents[1])

# Writes its pid file at once and stays until killed, as pasta --foreground
# does once it has connected a namespace; the namespace keeps only loopback.
FAKE_PASTA = """\
import sys, time
args = sys.argv[1:]
with open(args[args.index("--pid") + 1], "w") as handle:
    handle.write("1\\n")
time.sleep(600)
"""

# The session's own steps up to Xvfb, in the namespace browser.py makes.
PROBE = """\
import time
from pathlib import Path
from browser_fetch import browser, session
work = Path(sys.argv[1])
(work / browser.NETWORK_READY).write_text("")
until = time.monotonic() + 20
session.private_tmp([work])
session.await_network(work, until)
session.loopback_up()
session.drop_capabilities()
xvfb, display = session.start_xvfb(until)
xvfb.terminate()
print("ok", display)
"""


def run_in_namespace(code: str, work: Path) -> subprocess.CompletedProcess[str]:
    """Run Python code as init of the session's namespace kind, with work as argv[1]."""
    argv = [
        tools.UNSHARE,
        "--user",
        "--map-current-user",
        "--keep-caps",
        "--mount",
        "--net",
        "--pid",
        "--fork",
        "--kill-child",
        "--mount-proc",
        "--",
        sys.executable,
        "-I",
        "-c",
        f"import sys\nsys.path.insert(0, {ROOT!r})\n{code}",
        str(work),
    ]
    return subprocess.run(argv, capture_output=True, text=True, timeout=60, check=False)


def write_fake_pasta(directory: Path) -> str:
    """Install the stand-in pasta in directory and return its path."""
    path = directory / "pasta"
    path.write_text(f"#!{sys.executable} -I\n{FAKE_PASTA}")
    path.chmod(0o700)
    return str(path)


@functools.cache
def unavailable() -> str | None:
    """Why the host cannot run the session's namespace and Xvfb, or None when it can.

    The probe makes the same user, mount, network and PID namespace as
    browser.py and takes the session's own steps in it, so a host that
    refuses any of them (a sandbox without user namespaces, AppArmor's
    unprivileged user namespace restriction) is named rather than failed.
    """
    if tools.UNSHARE.startswith("@"):
        return "the source tree's tools are not store paths; run against the installed package"
    with tempfile.TemporaryDirectory(prefix="browser-fetch-probe-") as work:
        try:
            ran = run_in_namespace(PROBE, Path(work))
        except subprocess.TimeoutExpired:
            return "the namespace probe did not finish within 60 s"
    if ran.returncode == 0 and ran.stdout.startswith("ok"):
        return None
    tail = (ran.stderr or ran.stdout).strip().splitlines()[-1:] or [f"exit {ran.returncode}"]
    return f"the session's namespace or Xvfb cannot start here: {tail[0][:300]}"


def require_namespaces() -> None:
    """Skip the calling test class, saying why on stderr, when the probe fails."""
    reason = unavailable()
    if reason is not None:
        print(f"\nskipping namespace tests: {reason}", file=sys.stderr, flush=True)
        raise unittest.SkipTest(reason)


def tools_with(pasta: str, session: str = tools.SESSION) -> browser.Tools:
    """The installed tools, with the given pasta and session executables."""
    return browser.Tools(tools.UNSHARE, session, tools.CAMOUFOX_VERSION, pasta)
