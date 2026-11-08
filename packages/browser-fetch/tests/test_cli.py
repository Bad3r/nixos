# Copyright (c) 2026 Bad3r
"""The command line: the JSON record, exit codes, and the work directory."""

import dataclasses
import fcntl
import io
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
import unittest.mock
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

from browser_fetch import cli, fetch
from browser_fetch import cookies as jar

from tests.fakes import FakeBrowser, fake_curl, public

cli_browser = cli.camoufox

SECRET = "s3cr3t-session-value"  # noqa: S105 - a stand-in cookie value


class RecordTest(unittest.TestCase):
    """The JSON record's text window."""

    def test_window_counts_utf16(self) -> None:
        """Offset and length are UTF-16 code units, as the plugin counts them."""
        page = fetch.Page(
            "ok", "https://example.org/", 200, content_type="text/plain", text="a😀bc"
        )
        record = cli.record(page, 2, 2)
        self.assertEqual((record["length"], record["text"]), (5, "\ude00b"))
        self.assertEqual(json.loads(json.dumps(record))["text"], "\ude00b")

    def test_flags(self) -> None:
        """The record says whether the URL is preapproved and the type binary."""
        page = fetch.Page("ok", "https://docs.python.org/3/", 200, content_type="application/pdf")
        record = cli.record(page, 0, None)
        self.assertTrue(record["preapproved"])
        self.assertTrue(record["binary"])
        self.assertNotIn("savedPath", record)

    def test_converted_document_is_not_binary(self) -> None:
        """A PDF a converter turned into text pages like text, so it gets the read-on note."""
        raw = fetch.Page("ok", "https://example.org/a.pdf", 200, content_type="application/pdf")
        converted = dataclasses.replace(raw, text="# Title", converted=True)
        self.assertTrue(cli.record(raw, 0, None)["binary"])
        self.assertFalse(cli.record(converted, 0, None)["binary"])


class MainTest(unittest.TestCase):
    """main() against a fake curl."""

    def setUp(self) -> None:
        """Point the work directory at a fresh runtime dir and install the fake curl."""
        self.fake, self.holder = fake_curl()
        self.runtime = Path(tempfile.mkdtemp(prefix="browser-fetch-runtime-"))
        env = unittest.mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(self.runtime)})
        env.start()
        self.addCleanup(env.stop)
        curl_patch = unittest.mock.patch.object(cli.tools, "CURL", self.fake.path)
        lookup_patch = unittest.mock.patch.object(cli.urls, "lookup", side_effect=public)
        for patch in (curl_patch, lookup_patch):
            patch.start()
            self.addCleanup(patch.stop)
        cookie = jar.Cookie("session", SECRET, "example.org", "/", 2**62, secure=True, created=1)
        self.browser = FakeBrowser(own=[cookie])
        browser_patch = unittest.mock.patch.object(cli, "camoufox", return_value=self.browser)
        browser_patch.start()
        self.addCleanup(browser_patch.stop)

    def tearDown(self) -> None:
        """Remove the fakes."""
        self.holder.cleanup()
        __import__("shutil").rmtree(self.runtime)

    def run_main(self, *argv: str) -> tuple[int, str, str]:
        """Run main and return its status, stdout and stderr."""
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            status = cli.main(list(argv))
        return status, out.getvalue(), err.getvalue()

    def test_success_leaves_no_work_directory(self) -> None:
        """A fetch prints the record and removes its work directory."""
        self.fake.serve(
            {
                "https://example.org/": {
                    "status": 200,
                    "headers": {"Content-Type": "text/plain"},
                    "body": "hi",
                }
            }
        )
        status, out, _ = self.run_main("--json", "https://example.org/")
        self.assertEqual(status, 0)
        self.assertEqual(json.loads(out)["text"], "hi")
        self.assertEqual(list(self.runtime.iterdir()), [])

    def test_failure_leaves_no_work_directory_and_no_cookie(self) -> None:
        """A failed fetch exits 4, masks the cookie and removes its work directory."""
        self.fake.serve(
            {"https://example.org/": {"status": 0, "exit": 99, "stderr": f"cookie {SECRET}\n"}}
        )
        status, out, err = self.run_main("--json", "https://example.org/")
        self.assertEqual((status, out), (cli.FETCH_EXIT, ""))
        self.assertTrue(err.startswith("browser-fetch: "))
        self.assertNotIn(SECRET, err)
        self.assertEqual(list(self.runtime.iterdir()), [])

    def test_unwritable_state_still_fetches_with_curl(self) -> None:
        """With no usable browser state, a page curl can fetch is still fetched, in both modes."""
        self.fake.serve(
            {"https://example.org/": {"status": 200, "headers": {"Content-Type": "text/plain"}}}
        )
        state = self.runtime.parent / f"{self.runtime.name}-state"
        state.mkdir(mode=0o500)
        self.addCleanup(state.rmdir)
        self.addCleanup(state.chmod, 0o700)
        with (
            unittest.mock.patch.object(cli, "camoufox", cli_browser),
            unittest.mock.patch.dict(os.environ, {"XDG_STATE_HOME": str(state)}),
        ):
            for mode in ("never", "auto"):
                with self.subTest(mode=mode):
                    status, out, _ = self.run_main(
                        "--json", "--browser", mode, "https://example.org/"
                    )
                    self.assertEqual((status, json.loads(out)["via"]), (0, "curl"))

    def test_owner_file_is_locked_before_it_is_named(self) -> None:
        """A sweep can never find a run's owner file unlocked."""
        workdir = self.runtime / f"{cli.WORK_PREFIX}race"
        workdir.mkdir()
        named_at_lock: list[bool] = []
        flock = fcntl.flock

        def watch(fd: int, operation: int) -> None:
            named_at_lock.append((workdir / cli.OWNER).exists())
            flock(fd, operation)

        with unittest.mock.patch.object(cli.fcntl, "flock", watch):
            os.close(cli.claim(workdir))
        self.assertEqual(named_at_lock, [False])
        self.assertTrue((workdir / cli.OWNER).exists())

    def test_invalid_url(self) -> None:
        """An invalid URL exits 2 before any request."""
        status, _, err = self.run_main("http://localhost/")
        self.assertEqual(status, cli.USAGE_EXIT)
        self.assertIn("without a dot", err)
        self.assertEqual(self.fake.calls(), [])

    def test_unexpected_error_is_one_line_without_secrets(self) -> None:
        """Any other exception exits 7 with its type alone: no traceback, no message."""
        with unittest.mock.patch.object(
            fetch, "fetch", side_effect=RuntimeError(f"cookie {SECRET}")
        ):
            status, out, err = self.run_main("https://example.org/")
        self.assertEqual((status, out), (cli.INTERNAL_EXIT, ""))
        self.assertEqual(err, "browser-fetch: unexpected RuntimeError\n")

    def test_cookie_warnings_are_in_the_record_and_on_stderr(self) -> None:
        """Cookies a busy profile kept out are reported, and the page still comes back."""
        self.browser.store_error = cli.browser.BrowserError("busy")
        self.fake.serve(
            {
                "https://example.org/": {
                    "status": 200,
                    "headers": {"Content-Type": "text/plain", "Set-Cookie": "a=1; Max-Age=60"},
                    "body": "hi",
                }
            }
        )
        status, out, err = self.run_main("--json", "https://example.org/")
        warning = "1 cookie changes were not saved: busy"
        self.assertEqual((status, json.loads(out)["warnings"]), (0, [warning]))
        self.assertEqual(err, f"browser-fetch: warning: {warning}\n")

    def test_warnings_come_before_the_error(self) -> None:
        """A failed fetch's warnings are printed first, so the last line is the error."""
        self.browser.store_error = cli.browser.BrowserError("busy")
        self.fake.serve(
            {
                "https://example.org/": {
                    "status": 302,
                    "headers": {"Location": "/next", "Set-Cookie": "a=1; Max-Age=60"},
                }
            }
        )
        status, _, err = self.run_main("https://example.org/")
        lines = err.splitlines()
        self.assertEqual(status, cli.FETCH_EXIT)
        self.assertEqual(lines[0], "browser-fetch: warning: 1 cookie changes were not saved: busy")
        self.assertTrue(lines[-1].startswith("browser-fetch: request to https://example.org/next"))

    def test_unusable_jar_exits_3(self) -> None:
        """A cookie database that cannot be used safely exits 3 with the reason."""
        self.browser.jar_error = jar.CookieError("schema version 18")
        status, out, err = self.run_main("https://example.org/")
        self.assertEqual(
            (status, out, err), (cli.COOKIE_EXIT, "", "browser-fetch: schema version 18\n")
        )

    def test_no_cookies_reads_and_writes_nothing(self) -> None:
        """--no-cookies leaves the jar alone, both ways."""
        self.fake.serve(
            {
                "https://example.org/": {
                    "status": 200,
                    "headers": {"Content-Type": "text/plain", "Set-Cookie": "a=1; Max-Age=60"},
                }
            }
        )
        status, _, _ = self.run_main("--no-cookies", "https://example.org/")
        self.assertEqual((status, self.browser.reads, self.browser.stored), (0, 0, []))
        self.assertNotIn("Cookie:", self.fake.calls()[0]["config"])


class SweepTest(unittest.TestCase):
    """Work directories left by a killed run, and those of live runs."""

    def setUp(self) -> None:
        """A runtime directory to sweep."""
        self.runtime = Path(tempfile.mkdtemp(prefix="browser-fetch-runtime-"))
        self.addCleanup(lambda: __import__("shutil").rmtree(self.runtime, ignore_errors=True))

    def workdir(self, name: str, *, owner: bool = True) -> Path:
        """A work directory, with an owner file unless told otherwise."""
        path = self.runtime / f"{cli.WORK_PREFIX}{name}"
        path.mkdir()
        if owner:
            (path / cli.OWNER).touch()
        return path

    def test_unlocked_owner_is_gone(self) -> None:
        """No lock on the owner file means the run died: its directory goes."""
        self.workdir("1-dead")
        cli.sweep(self.runtime)
        self.assertEqual(list(self.runtime.iterdir()), [])

    def test_locked_owner_is_alive_whatever_its_pid(self) -> None:
        """A held lock keeps the directory, even under a PID no process here has."""
        live = self.workdir("999999999-other-namespace")
        fd = os.open(live / cli.OWNER, os.O_RDWR)
        fcntl.flock(fd, fcntl.LOCK_EX)
        try:
            cli.sweep(self.runtime)
            self.assertEqual(list(self.runtime.iterdir()), [live])
        finally:
            os.close(fd)

    def test_vanishing_entry_is_not_an_error(self) -> None:
        """A directory removed between the listing and its inspection is skipped."""
        self.workdir("1-racing")
        real_stat = Path.stat

        def vanish(path: Path, **kwargs: object) -> os.stat_result:
            if path.name.endswith("racing"):
                raise FileNotFoundError(path)
            return real_stat(path, **kwargs)  # type: ignore[arg-type]

        with unittest.mock.patch.object(Path, "stat", vanish):
            cli.sweep(self.runtime)

    def test_ownerless_directory_waits_for_its_owner(self) -> None:
        """A directory without an owner file is kept until it is old."""
        young = self.workdir("1-young", owner=False)
        old = self.workdir("2-old", owner=False)
        stale = time.time() - cli.ORPHAN_SECONDS - 10
        os.utime(old, (stale, stale))
        cli.sweep(self.runtime)
        self.assertEqual(list(self.runtime.iterdir()), [young])


class SignalTest(unittest.TestCase):
    """SIGTERM mid-fetch still removes the work directory."""

    def test_sigterm(self) -> None:
        """A terminated run exits 143 and leaves nothing behind."""
        with tempfile.TemporaryDirectory(prefix="browser-fetch-runtime-") as runtime:
            script = (
                "import sys, time, unittest.mock\n"
                "from browser_fetch import cli, fetch\n"
                "def slow(url, settings):\n"
                "    print('started', flush=True)\n"
                "    time.sleep(30)\n"
                "with unittest.mock.patch.object(fetch, 'fetch', slow):\n"
                "    sys.exit(cli.main(['https://example.org/']))\n"
            )
            child = subprocess.Popen(
                [
                    sys.executable,
                    "-I",
                    "-c",
                    f"import sys; sys.path.insert(0, {str(Path.cwd())!r})\n{script}",
                ],
                env={**os.environ, "XDG_RUNTIME_DIR": runtime},
                stdout=subprocess.PIPE,
                text=True,
            )
            if child.stdout is None:
                self.fail("no pipe to the child")
            self.assertEqual(child.stdout.readline().strip(), "started")
            self.assertEqual(len(list(Path(runtime).iterdir())), 1)
            child.send_signal(signal.SIGTERM)
            self.assertEqual(child.wait(timeout=10), 128 + signal.SIGTERM)
            child.stdout.close()
            self.assertEqual(list(Path(runtime).iterdir()), [])
