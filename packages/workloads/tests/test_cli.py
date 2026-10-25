# Copyright (c) 2026 Bad3r
"""Behavior of the workloads command line."""

import contextlib
import io
import json
import tempfile
import unittest
import unittest.mock
from pathlib import Path
from typing import TYPE_CHECKING

from workloads.cli import SbxRunner, WorkloadsError, main, names, sandboxes

if TYPE_CHECKING:
    from collections.abc import Sequence

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
        code, out, err = run(lambda _: None, "--json")
        self.assertEqual(code, 0)
        report = json.loads(out)
        self.assertIsNone(report["sandboxes"])
        self.assertEqual(report["names"][0]["name"], "dev")
        self.assertIn("sbx is not installed", err)

    def test_with_sbx(self) -> None:
        """Live sandboxes join the table under their domain name."""
        code, out, err = run(lambda _: (0, json.dumps([SANDBOX])))
        self.assertEqual((code, err), (0, ""))
        self.assertIn("sbx-ab12", out)
        self.assertIn("host.vm", out)

    def test_sbx_failure(self) -> None:
        """A failing sbx fails the command with its message."""
        error = json.dumps({"error": {"code": "x", "message": "no session daemon"}})
        with self.assertRaisesRegex(WorkloadsError, "no session daemon"):
            sandboxes(lambda _: (1, error))
        code, out, _ = run(lambda _: (1, error), "--json")
        self.assertEqual(code, 1)
        self.assertEqual(json.loads(out)["error"]["code"], "sbx")

    def test_malformed_input(self) -> None:
        """Malformed sbx items and names files fail with a code instead of a traceback."""
        with self.assertRaisesRegex(WorkloadsError, "malformed sandbox"):
            sandboxes(lambda _: (0, json.dumps([{"name": "ab12"}])))
        with self.assertRaises(WorkloadsError) as caught:
            names({"names": [], "networks": {}}, lambda _: None)
        self.assertEqual(caught.exception.code, "names-file")

    def test_empty_registry(self) -> None:
        """A host without declared names lists nothing instead of failing."""
        report = names({"names": {}, "networks": {}}, lambda _: None)
        self.assertEqual((report["names"], report["resolvers"]), ([], {}))


class FakeHelper:
    """Answers grant requests and keeps them."""

    def __init__(self, answer: dict[str, object]) -> None:
        """Answer every request with `answer`."""
        self.answer = answer
        self.requests: list[dict[str, object]] = []

    def __call__(self, request: dict[str, object]) -> dict[str, object]:
        """Record and answer."""
        self.requests.append(request)
        return self.answer


def run_grant(helper: FakeHelper, runner: SbxRunner, *argv: str) -> tuple[int, str, str]:
    """Run a grant verb against a fake helper."""
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = main(Path("/nonexistent"), list(argv), runner, helper)
    return code, out.getvalue(), err.getvalue()


GRANT: dict[str, object] = {
    "id": "0000000a",
    "source": "sbx-ab12",
    "target": "host:dev",
    "expires_in": 1800,
    "paths": [],
}


class GrantVerbsTest(unittest.TestCase):
    """grant, revoke, and grants build helper requests and print answers."""

    def test_sandbox_grant(self) -> None:
        """A sandbox source sends the address sbx reports and the TTL in seconds."""
        helper = FakeHelper({"grant": GRANT})
        calls: list[list[str]] = []

        def runner(arguments: Sequence[str]) -> tuple[int, str]:
            calls.append(list(arguments))
            return 0, json.dumps(SANDBOX | {"address": "172.16.2.50"})

        code, out, _ = run_grant(helper, runner, "grant", "sbx-ab12", "host:dev", "--ttl", "2h")
        self.assertEqual(code, 0)
        self.assertEqual(calls, [["info", "ab12", "--json"]])
        request = helper.requests[0]
        request.pop("session", None)
        self.assertEqual(
            request,
            {
                "verb": "grant",
                "source": "sbx-ab12",
                "target": "host:dev",
                "ttl": 7200,
                "address": "172.16.2.50",
            },
        )
        self.assertIn("0000000a  sbx-ab12 -> host:dev  expires in 30m", out)

    def test_guest_grant(self) -> None:
        """A bare name is a guest and sends no address; the default TTL is 30m."""
        helper = FakeHelper({"grant": GRANT})
        code, _, _ = run_grant(helper, lambda _: None, "grant", "nixos-dev", "host:llm")
        self.assertEqual(code, 0)
        self.assertEqual(
            {key: helper.requests[0][key] for key in ("source", "ttl")},
            {"source": "guest:nixos-dev", "ttl": 1800},
        )
        self.assertNotIn("address", helper.requests[0])

    def test_sandbox_without_address(self) -> None:
        """A sandbox off every workload network fails before the helper."""
        helper = FakeHelper({"grant": GRANT})
        code, out, _ = run_grant(
            helper, lambda _: (0, json.dumps(SANDBOX)), "grant", "--json", "sbx-ab12", "host:dev"
        )
        self.assertEqual((code, json.loads(out)["error"]["code"]), (1, "no-address"))
        self.assertEqual(helper.requests, [])

    def test_refusal(self) -> None:
        """The helper's error code and message pass through."""
        helper = FakeHelper({"error": {"code": "ttl", "message": "too long"}})
        code, out, _ = run_grant(
            helper, lambda _: None, "--json", "grant", "dev", "host:dev", "--ttl", "3d"
        )
        self.assertEqual(
            (code, json.loads(out)["error"]), (1, {"code": "ttl", "message": "too long"})
        )
        code, _, err = run_grant(
            helper, lambda _: None, "grant", "dev", "host:dev", "--ttl", "soon"
        )
        self.assertEqual(code, 1)
        self.assertIn("not a duration", err)

    def test_session(self) -> None:
        """The agent session rides along."""
        helper = FakeHelper({"grants": []})
        with unittest.mock.patch.dict("os.environ", {"CLAUDE_CODE_SESSION_ID": "s1"}, clear=True):
            run_grant(helper, lambda _: None, "grants")
        self.assertEqual(helper.requests, [{"verb": "list", "session": "claude:s1"}])

    def test_revoke(self) -> None:
        """Revoke takes an id or --all with a source."""
        helper = FakeHelper({"revoked": ["0000000a"]})
        with unittest.mock.patch.dict("os.environ", {}, clear=True):
            code, out, _ = run_grant(helper, lambda _: None, "revoke", "0000000a")
            run_grant(helper, lambda _: None, "revoke", "--all", "nixos-dev")
            usage, _, _ = run_grant(helper, lambda _: None, "revoke")
        self.assertEqual((code, out), (0, "revoked 0000000a\n"))
        self.assertEqual(
            helper.requests,
            [{"verb": "revoke", "id": "0000000a"}, {"verb": "revoke", "source": "guest:nixos-dev"}],
        )
        self.assertEqual(usage, 2)

    def test_grants_table(self) -> None:
        """Live grants print as a table."""
        helper = FakeHelper({"grants": [GRANT]})
        code, out, _ = run_grant(helper, lambda _: None, "grants")
        self.assertEqual(code, 0)
        self.assertEqual(out.splitlines()[0].split(), ["ID", "SOURCE", "TARGET", "EXPIRES", "IN"])
        self.assertIn("sbx-ab12", out)


# A sandbox creation token, not a credential.
CREATION = "c" * 16
VSOCK_SANDBOX = SANDBOX | {"token": CREATION}


def vsock_runner(state: dict[str, object], calls: list[list[str]]) -> SbxRunner:
    """Sbx reporting a sandbox without a network, and the proxy's grant states."""

    def runner(arguments: Sequence[str]) -> tuple[int, str]:
        calls.append(list(arguments))
        if arguments[0] == "info":
            return 0, json.dumps(VSOCK_SANDBOX)
        return 0, json.dumps({"grants": state, "list_error": None})

    return runner


class VsockVerbsTest(unittest.TestCase):
    """A sandbox without a network is granted by its creation and confirmed by its proxy."""

    def test_grant(self) -> None:
        """The token goes to the helper, and the grant stands once its listener is placed."""
        helper = FakeHelper({"grant": GRANT})
        calls: list[list[str]] = []
        runner = vsock_runner({"0000000a": {"state": "listening"}}, calls)
        code, _, _ = run_grant(helper, runner, "grant", "sbx-ab12", "host:dev")
        self.assertEqual(code, 0)
        self.assertEqual(helper.requests[0]["token"], CREATION)
        self.assertNotIn("address", helper.requests[0])
        self.assertEqual(calls[-1], ["vsock", "sync", "--json"])
        self.assertEqual(len(helper.requests), 1)

    def test_unplaced_grant_is_revoked(self) -> None:
        """A listener outside the sandbox's namespace leaves nothing granted."""
        helper = FakeHelper({"grant": GRANT})
        state: dict[str, object] = {
            "0000000a": {"state": "failed", "error": "vsock mode is global"}
        }
        with unittest.mock.patch.dict("os.environ", {}, clear=True):
            code, out, _ = run_grant(
                helper, vsock_runner(state, []), "--json", "grant", "sbx-ab12", "host:dev"
            )
        error = json.loads(out)["error"]
        self.assertEqual((code, error["code"]), (1, "vsock-listener"))
        self.assertIn("vsock mode is global", error["message"])
        self.assertEqual(helper.requests[-1], {"verb": "revoke", "id": "0000000a"})

    def test_revoke_settles(self) -> None:
        """Revoke returns once the proxy no longer serves the grant."""
        helper = FakeHelper({"revoked": ["0000000a"], "vsock": ["0000000a"]})
        calls: list[list[str]] = []
        with unittest.mock.patch.dict("os.environ", {}, clear=True):
            code, _, _ = run_grant(helper, vsock_runner({}, calls), "revoke", "0000000a")
            stuck = vsock_runner({"0000000a": {"state": "listening"}}, [])
            failed, out, _ = run_grant(helper, stuck, "--json", "revoke", "0000000a")
        self.assertEqual((code, calls), (0, [["vsock", "sync", "--json"]]))
        self.assertEqual((failed, json.loads(out)["error"]["code"]), (1, "vsock-unconfirmed"))
        self.assertIn("revoked from the vsock grant list", json.loads(out)["error"]["message"])
        unreachable = json.dumps({"error": {"code": "vsock-proxy", "message": "not reachable"}})
        with unittest.mock.patch.dict("os.environ", {}, clear=True):
            failed, out, _ = run_grant(
                helper, lambda _: (1, unreachable), "--json", "revoke", "0000000a"
            )
        error = json.loads(out)["error"]
        self.assertEqual((failed, error["code"]), (1, "vsock-unconfirmed"))
        self.assertIn("not reachable", error["message"])
