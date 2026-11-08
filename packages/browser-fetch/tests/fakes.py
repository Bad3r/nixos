# Copyright (c) 2026 Bad3r
"""A stand-in for curl-impersonate that serves canned responses."""

from __future__ import annotations

import json
import os
import stat
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, cast

SCRIPT = """\
import json, os, stat, sys
args = sys.argv[1:]
config = args[args.index("--config") + 1]
output = args[args.index("--output") + 1]
url = args[-1]
mode = stat.S_IMODE(os.stat(config).st_mode)
with open(config) as handle:
    config_text = handle.read()
with open(os.environ["FAKE_CURL_LOG"], "a") as log:
    log.write(json.dumps({"argv": args, "config": config_text, "mode": mode}) + "\\n")
routes = json.load(open(os.environ["FAKE_CURL_ROUTES"]))
route = routes.get(url)
if route is None:
    sys.stderr.write("curl: (6) Could not resolve host\\n")
    sys.exit(6)
if route.get("exit"):
    sys.stderr.write(route.get("stderr", ""))
    sys.exit(route["exit"])
with open(output, "wb") as body:
    body.write(route.get("body", "").encode())
headers = {k.lower(): [v] for k, v in route.get("headers", {}).items()}
pinned = args[args.index("--resolve") + 1].split(":", 2)[2].split(",")[0].strip("[]")
remote = route.get("remote_ip", pinned)
sys.stdout.write(f"{route['status']}\\n{remote}\\n{json.dumps(headers)}")
"""
PUBLIC_ADDRESS = "93.184.215.14"


def public(host: str, port: int) -> list[str]:  # noqa: ARG001
    """A resolver that answers every name with one public address."""
    return [PUBLIC_ADDRESS]


@dataclass
class FakeCurl:
    """A fake curl executable, its routes and its call log."""

    root: Path

    @property
    def path(self) -> str:
        """The executable."""
        return str(self.root / "curl")

    def serve(self, routes: dict[str, dict[str, Any]]) -> None:
        """Answer each URL with its status, headers, body or exit code."""
        (self.root / "routes.json").write_text(json.dumps(routes))

    def calls(self) -> list[dict[str, Any]]:
        """Return each call's argv, config text and config file mode."""
        log = self.root / "log.jsonl"
        if not log.exists():
            return []
        return [cast("dict[str, Any]", json.loads(line)) for line in log.read_text().splitlines()]


def fake_curl() -> tuple[FakeCurl, tempfile.TemporaryDirectory[str]]:
    """Install a fake curl in a new directory and point the environment at it."""
    holder = tempfile.TemporaryDirectory(prefix="fake-curl-")
    root = Path(holder.name)
    script = root / "curl"
    script.write_text(f"#!{sys.executable} -I\n{SCRIPT}")
    script.chmod(stat.S_IRWXU)
    os.environ["FAKE_CURL_LOG"] = str(root / "log.jsonl")
    os.environ["FAKE_CURL_ROUTES"] = str(root / "routes.json")
    fake = FakeCurl(root)
    fake.serve({})
    return fake, holder


@dataclass
class FakeBrowser:
    """A stand-in for the Camoufox fallback: an identity, a jar and canned renders."""

    identity_value: Any = None
    own: list[Any] | None = None
    rendered: Any = None
    error: Exception | None = None
    calls: list[dict[str, Any]] | None = None

    def identity(self, until: float) -> Any:  # noqa: ANN401, ARG002
        """The canned identity."""
        return self.identity_value

    def jar(self, until: float) -> list[Any]:  # noqa: ARG002
        """The canned own cookies."""
        return list(self.own or [])

    def render(self, url: str, librewolf: list[Any], received: list[Any], until: float) -> Any:  # noqa: ANN401, ARG002
        """Record the call and return the canned result or raise the canned error."""
        if self.calls is None:
            self.calls = []
        self.calls.append({"url": url, "librewolf": librewolf, "received": received})
        if self.error is not None:
            raise self.error
        return self.rendered
