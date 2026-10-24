# Copyright (c) 2026 Bad3r
"""Behavior of `workloads names`."""

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

from workloads.cli import SbxRunner, WorkloadsError, main, names, sandboxes

DECLARED = {
    "names": {"dev": {"address": "172.16.1.10", "kind": "guest", "network": "desktop"}},
    "networks": {"desktop": {"172.16.1.1": ["host.vm"]}},
}
SANDBOX = {"name": "ab12", "domain": "sbx-ab12", "address": None, "net": "none", "state": "running"}


def run(runner: SbxRunner, *argv: str) -> tuple[int, str, str]:
    """Run main on DECLARED and capture its exit code, stdout, and stderr."""
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "names.json"
        path.write_text(json.dumps(DECLARED))
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = main(path, ["names", *argv], runner)
    return code, out.getvalue(), err.getvalue()


class NamesTest(unittest.TestCase):
    """Declared names always list; sandboxes list only when sbx runs."""

    def test_without_sbx(self) -> None:
        """A host without sbx says so and reports null sandboxes."""
        code, out, err = run(lambda: None, "--json")
        self.assertEqual(code, 0)
        report = json.loads(out)
        self.assertIsNone(report["sandboxes"])
        self.assertEqual(report["names"][0]["name"], "dev")
        self.assertIn("sbx is not installed", err)

    def test_with_sbx(self) -> None:
        """Live sandboxes join the table under their domain name."""
        code, out, err = run(lambda: (0, json.dumps([SANDBOX])))
        self.assertEqual((code, err), (0, ""))
        self.assertIn("sbx-ab12", out)
        self.assertIn("host.vm", out)

    def test_sbx_failure(self) -> None:
        """A failing sbx fails the command with its message."""
        error = json.dumps({"error": {"code": "x", "message": "no session daemon"}})
        with self.assertRaisesRegex(WorkloadsError, "no session daemon"):
            sandboxes(lambda: (1, error))
        code, out, _ = run(lambda: (1, error), "--json")
        self.assertEqual(code, 1)
        self.assertEqual(json.loads(out)["error"]["code"], "sbx")

    def test_malformed_input(self) -> None:
        """Malformed sbx items and names files fail with a code instead of a traceback."""
        with self.assertRaisesRegex(WorkloadsError, "malformed sandbox"):
            sandboxes(lambda: (0, json.dumps([{"name": "ab12"}])))
        with self.assertRaises(WorkloadsError) as caught:
            names({"names": [], "networks": {}}, lambda: None)
        self.assertEqual(caught.exception.code, "names-file")
