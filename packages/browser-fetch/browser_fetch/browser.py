# Copyright (c) 2026 Bad3r
"""Camoufox with one persistent profile and identity, run by session.py in a namespace."""

from __future__ import annotations

import ctypes
import fcntl
import hashlib
import json
import os
import shutil
import signal
import sqlite3
import subprocess
import time
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any, cast

from browser_fetch import cookies as jar
from browser_fetch import curl

if TYPE_CHECKING:
    from collections.abc import Callable, Iterable, Mapping
    from pathlib import Path

# Bounds of one fallback: waiting for another fetch's browser, then the
# session's own start, load and challenge wait, which session.py splits.
LOCK_SECONDS = 90
GENERATE_SECONDS = 90
FINGERPRINT = "fingerprint.json"
JOURNAL = "injected.json"
LOCK = "camoufox.lock"
PROFILE = "profile"
HOME = "home"
_PR_SET_PDEATHSIG = 1
_POLL_SECONDS = 0.1
# Gecko refuses a cookie that outlives network.cookie.maxageCap (400 days,
# CookieValidation.cpp) when added directly; Set-Cookie clamps it instead.
MAXAGE_CAP_SECONDS = 34_560_000
_CAP_MARGIN_SECONDS = 3600
_ENV_KEEP = ("LANG", "LC_ALL", "TZ", "https_proxy", "HTTPS_PROXY", "no_proxy", "NO_PROXY")


class BrowserError(Exception):
    """The browser could not start or render the page."""


@dataclass(frozen=True)
class Tools:
    """What the fallback runs: unshare, and the session entry point inside it."""

    unshare: str
    session: str
    camoufox_version: str


@dataclass(frozen=True)
class Blocked:
    """The first main-document hop the redirect policy stopped before it was sent."""

    origin: str
    target: str
    status: int


@dataclass(frozen=True)
class Rendered:
    """The document the browser ended on: its DOM as text, or the bytes of another type."""

    url: str
    status: int
    content_type: str
    html: str | None = None
    body: bytes = b""
    blocked: Blocked | None = None


def _die_with_parent() -> None:
    libc = ctypes.CDLL(None, use_errno=True)
    libc.prctl(_PR_SET_PDEATHSIG, signal.SIGKILL)


def _write_private(path: Path, data: bytes) -> None:
    """Replace path atomically with a 0600 file holding data."""
    partial = path.with_name(f".{path.name}.partial")
    fd = os.open(partial, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "wb") as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())
    partial.replace(path)


def digest(value: str) -> str:
    """The sha256 the journal keeps of a value, never the value."""
    return hashlib.sha256(value.encode("utf-8", "surrogatepass")).hexdigest()


def playwright_cookie(cookie: jar.Cookie, now: float | None = None) -> dict[str, Any]:
    """The cookie as Playwright's add_cookies takes it; Gecko's host form is kept.

    The expiry is clamped to Gecko's cap, as a Set-Cookie would have been.
    """
    cap = (time.time() if now is None else now) + MAXAGE_CAP_SECONDS - _CAP_MARGIN_SECONDS
    if cookie.same_site == jar.SAME_SITE_STRICT:
        same_site = "Strict"
    elif cookie.same_site == jar.SAME_SITE_LAX or not cookie.secure:
        # Gecko refuses SameSite=None without Secure; unset acts as None otherwise.
        same_site = "Lax"
    else:
        same_site = "None"
    return {
        "name": cookie.name,
        "value": cookie.value,
        "domain": cookie.host,
        "path": cookie.path,
        "expires": -1 if cookie.session else min(cookie.expiry_ms / 1000, cap),
        "httpOnly": cookie.http_only,
        "secure": cookie.secure,
        "sameSite": same_site,
    }


def injection(
    own: Iterable[jar.Cookie],
    librewolf: Iterable[jar.Cookie],
    received: Iterable[jar.Cookie],
    url: str,
    now: int,
) -> list[jar.Cookie]:
    """The cookies a fallback adds to the browser's jar for url's host.

    The site's responses during this fetch come first; a LibreWolf cookie
    goes in only where the browser holds none of that name, host and path,
    so a cookie the browser earned wins. Partitioned cookies stay out:
    Playwright adds to the unpartitioned jar only.
    """
    held = {cookie.key for cookie in own}
    fresh = list(received)
    taken = {cookie.key for cookie in fresh}
    chosen = fresh + [c for c in librewolf if c.key not in held and c.key not in taken]
    return [c for c in jar.for_host(chosen, url, now) if not c.partition]


def purge(database: Path, journal: list[dict[str, str]]) -> int:
    """Delete each journaled cookie whose value is still the one injected.

    A cookie the site set anew during the session has another value and
    stays; so does every cookie the browser had of its own.
    """
    if not journal or not database.exists():
        return 0
    connection = sqlite3.connect(database, timeout=10)
    removed = 0
    try:
        for entry in journal:
            rows: list[tuple[int, str]] = connection.execute(
                "select id, coalesce(value, '') from moz_cookies"
                " where coalesce(name, '') = ? and host = ? and path = ?"
                " and originAttributes = ''",
                (entry["name"], entry["host"], entry["path"]),
            ).fetchall()
            doomed = [(rowid,) for rowid, value in rows if digest(value) == entry["digest"]]
            connection.executemany("delete from moz_cookies where id = ?", doomed)
            removed += len(doomed)
        connection.commit()
    except sqlite3.Error as error:
        msg = f"the browser's injected cookies could not be removed: {error}"
        raise BrowserError(msg) from None
    finally:
        connection.close()
    return removed


class Camoufox:
    """The fallback browser: one profile and one fingerprint under the state directory."""

    def __init__(
        self,
        tools: Tools,
        state: Path,
        workdir: Path,
        *,
        clock: Callable[[], float] = time.monotonic,
        environ: Mapping[str, str] | None = None,
    ) -> None:
        """Remember where the state lives; nothing is created yet."""
        self.tools = tools
        self.state = state
        self.workdir = workdir
        self.clock = clock
        self.environ = dict(os.environ if environ is None else environ)

    @property
    def profile(self) -> Path:
        """The persistent Firefox profile."""
        return self.state / PROFILE

    def _prepare(self) -> None:
        self.state.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.state.chmod(0o700)

    def _lock(self, until: float) -> int:
        """Take the profile lock, waiting at most LOCK_SECONDS and never past until.

        The lock lasts until the returned descriptor is closed.
        """
        self._prepare()
        fd = os.open(self.state / LOCK, os.O_RDWR | os.O_CREAT | os.O_CLOEXEC, 0o600)
        give_up = min(until, self.clock() + LOCK_SECONDS)
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                if self.clock() >= give_up:
                    os.close(fd)
                    msg = "another fetch kept the browser profile busy; try again"
                    raise BrowserError(msg) from None
                time.sleep(_POLL_SECONDS)
            else:
                return fd

    def _fingerprint(self) -> dict[str, Any] | None:
        try:
            data = json.loads((self.state / FINGERPRINT).read_text())
        except FileNotFoundError:
            return None
        except (OSError, ValueError) as error:
            msg = f"the browser fingerprint could not be read: {error}"
            raise BrowserError(msg) from None
        if not isinstance(data, dict):
            return None
        fingerprint = cast("dict[str, Any]", data)
        return fingerprint if fingerprint.get("browser") == self.tools.camoufox_version else None

    def identity(self, until: float) -> curl.Identity:
        """The fingerprint's User-Agent and Accept-Language, generated on first use.

        The fingerprint belongs to one browser release; another release
        draws a new one, since a User-Agent naming the old one would leak.
        """
        fingerprint = self._fingerprint()
        if fingerprint is None:
            lock = self._lock(until)
            try:
                fingerprint = self._fingerprint()
                if fingerprint is None:
                    self._session("generate", {}, min(until, self.clock() + GENERATE_SECONDS))
                    fingerprint = self._fingerprint()
            finally:
                os.close(lock)
            if fingerprint is None:
                msg = "the browser wrote no fingerprint"
                raise BrowserError(msg)
        headers = cast("dict[str, str]", fingerprint.get("headers", {}))
        return curl.Identity(headers["user-agent"], headers["accept-language"])

    def jar(self) -> list[jar.Cookie]:
        """The cookies of the browser's own profile, read from a consistent copy."""
        if not (self.profile / jar.DB_NAME).exists():
            return []
        into = self.workdir / "camoufox-jar"
        into.mkdir(mode=0o700, exist_ok=True)
        return jar.read(jar.snapshot(self.profile, into))

    def _recover(self) -> None:
        """Purge what a session killed before its own purge injected, and any disk cache."""
        shutil.rmtree(self.profile / "cache2", ignore_errors=True)
        journal_path = self.state / JOURNAL
        try:
            journal = json.loads(journal_path.read_text())
        except FileNotFoundError:
            return
        except OSError, ValueError:
            journal = []
        purge(self.profile / jar.DB_NAME, cast("list[dict[str, str]]", journal))
        journal_path.unlink(missing_ok=True)

    def render(
        self,
        url: str,
        librewolf: list[jar.Cookie],
        received: list[jar.Cookie],
        until: float,
    ) -> Rendered:
        """Load url in the browser with the cookies merged in, then take them out again."""
        lock = self._lock(until)
        try:
            self._recover()
            cookies = injection(self.jar(), librewolf, received, url, jar.now_ms())
            journal = [
                {"name": c.name, "host": c.host, "path": c.path, "digest": digest(c.value)}
                for c in cookies
            ]
            journal_path = self.state / JOURNAL
            _write_private(journal_path, json.dumps(journal).encode())
            try:
                result = self._session(
                    "render",
                    {"url": url, "cookies": [playwright_cookie(c) for c in cookies]},
                    until,
                )
            finally:
                purge(self.profile / jar.DB_NAME, journal)
                journal_path.unlink(missing_ok=True)
        finally:
            os.close(lock)
        return self._rendered(result)

    def _rendered(self, result: dict[str, Any]) -> Rendered:
        blocked = result.get("blocked")
        if isinstance(blocked, dict):
            stop = cast("dict[str, Any]", blocked)
            return Rendered(
                url=str(stop["origin"]),
                status=int(stop["status"]),
                content_type="",
                blocked=Blocked(str(stop["origin"]), str(stop["target"]), int(stop["status"])),
            )
        html: str | None = None
        body = b""
        if result.get("html"):
            html = (self.workdir / "page.html").read_text(encoding="utf-8", errors="surrogatepass")
        else:
            body = (self.workdir / "page.body").read_bytes()
        return Rendered(
            url=str(result["url"]),
            status=int(result.get("status") or 200),
            content_type=str(result.get("contentType") or "text/html"),
            html=html,
            body=body,
        )

    def _environment(self) -> dict[str, str]:
        env = {key: self.environ[key] for key in _ENV_KEEP if key in self.environ}
        env["PATH"] = "/var/empty"
        return env

    def _session(self, mode: str, request: dict[str, Any], until: float) -> dict[str, Any]:
        """Run session.py as init of a user, mount and PID namespace and read its result.

        The namespace's init dies with this process (PR_SET_PDEATHSIG on
        unshare, --kill-child on init), and the kernel then kills everything
        in it, Xvfb and the browser included, on any exit path.
        """
        seconds = until - self.clock()
        if seconds <= 1:
            msg = "no time was left for the browser"
            raise BrowserError(msg)
        request_path = self.workdir / "session.json"
        result_path = self.workdir / "result.json"
        result_path.unlink(missing_ok=True)
        _write_private(
            request_path,
            json.dumps(
                {
                    **request,
                    "mode": mode,
                    "state": str(self.state),
                    "workdir": str(self.workdir),
                    "seconds": seconds,
                }
            ).encode(),
        )
        argv = [
            self.tools.unshare,
            "--user",
            "--map-current-user",
            "--keep-caps",
            "--mount",
            "--pid",
            "--fork",
            "--kill-child",
            "--mount-proc",
            "--",
            self.tools.session,
            str(request_path),
        ]
        log = self.workdir / "session.log"
        with log.open("wb") as sink:
            process = subprocess.Popen(
                argv,
                stdin=subprocess.DEVNULL,
                stdout=sink,
                stderr=subprocess.STDOUT,
                env=self._environment(),
                cwd=self.workdir,
                preexec_fn=_die_with_parent,  # noqa: PLW1509 - prctl only, before exec
            )
        try:
            process.wait(timeout=max(seconds, 1.0))
        except subprocess.TimeoutExpired:
            msg = f"the browser took longer than {seconds:.0f} s"
            raise BrowserError(msg) from None
        finally:
            if process.poll() is None:
                process.kill()
            process.wait()
        try:
            result = cast("dict[str, Any]", json.loads(result_path.read_text()))
        except OSError, ValueError:
            tail = log.read_text(errors="replace").strip().splitlines()[-1:] or [""]
            msg = f"the browser exited {process.returncode} without a result {tail[0][:200]}"
            raise BrowserError(msg.strip()) from None
        if "error" in result:
            msg = f"the browser failed: {str(result['error'])[:300]}"
            raise BrowserError(msg)
        return result
