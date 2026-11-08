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
# A jar read waits this long for a session holding the profile, then goes
# on without the jar: it never stalls a fetch behind another one's render.
JAR_LOCK_SECONDS = 2
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
# The session's handshake files in the work directory (session.py).
NETNS_READY = "netns.ready"
NETWORK_READY = "network.ready"
NETWORK_SECONDS = 15
# pasta gives the namespace the host's outbound connectivity and nothing
# else: no host loopback or gateway mapping and no port forwarding either way.
PASTA_ARGS = (
    "--config-net",
    "--quiet",
    "--foreground",
    "--map-host-loopback", "none",
    "--map-guest-addr", "none",
    "--tcp-ports", "none",
    "--udp-ports", "none",
    "--tcp-ns", "none",
    "--udp-ns", "none",
)  # fmt: skip


class BrowserError(Exception):
    """The browser could not start or render the page."""


@dataclass(frozen=True)
class Tools:
    """What the fallback runs: unshare, the session inside it, and pasta for its network."""

    unshare: str
    session: str
    camoufox_version: str
    pasta: str


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


def write_private(path: Path, data: bytes) -> None:
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
    goes in only where the browser holds no live cookie of that name, host
    and path, so a cookie the browser earned wins. A cookie the site deleted
    during the fetch keeps LibreWolf's copy out too. Partitioned cookies stay
    out: Playwright adds to the unpartitioned jar only.
    """
    held = {cookie.key for cookie in jar.live(own, now)}
    fresh = list(received)
    taken = {cookie.key for cookie in fresh}
    chosen = fresh + [c for c in librewolf if c.key not in held and c.key not in taken]
    return [c for c in jar.for_host(chosen, url, now) if not c.partition]


def forget(database: Path, deleted: Iterable[jar.Cookie]) -> int:
    """Delete the browser's own unpartitioned cookies the site deleted during this fetch.

    The browser would have applied the same Set-Cookie had it made the request.
    """
    keys = [(c.name, c.host, c.path) for c in deleted if not c.partition]
    if not keys or not database.exists():
        return 0
    connection = sqlite3.connect(database, timeout=10)
    try:
        removed = 0
        for name, host, path in keys:
            removed += connection.execute(
                "delete from moz_cookies where coalesce(name, '') = ? and host = ? and path = ?"
                " and originAttributes = ''",
                (name, host, path),
            ).rowcount
        connection.commit()
    except sqlite3.Error as error:
        msg = f"the browser's deleted cookies could not be removed: {error}"
        raise BrowserError(msg) from None
    finally:
        connection.close()
    return removed


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

    def _lock(self, until: float, wait: float = LOCK_SECONDS) -> int:
        """Take the profile lock, waiting at most wait seconds and never past until.

        The lock lasts until the returned descriptor is closed.
        """
        try:
            self._prepare()
            fd = os.open(self.state / LOCK, os.O_RDWR | os.O_CREAT | os.O_CLOEXEC, 0o600)
        except OSError as error:
            msg = f"the browser's state directory {self.state} is unusable: {error.strerror}"
            raise BrowserError(msg) from None
        give_up = min(until, self.clock() + wait)
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
        except FileNotFoundError, NotADirectoryError:
            return None
        except (OSError, ValueError) as error:
            msg = f"the browser fingerprint could not be read: {error}"
            raise BrowserError(msg) from None
        if not isinstance(data, dict):
            return None
        fingerprint = cast("dict[str, Any]", data)
        return fingerprint if fingerprint.get("browser") == self.tools.camoufox_version else None

    def identity(self, until: float, *, generate: bool = True) -> curl.Identity | None:
        """The fingerprint's User-Agent and Accept-Language, generated on first use.

        The fingerprint belongs to one browser release; another release
        draws a new one, since a User-Agent naming the old one would leak.
        Drawing it starts the browser, which happens only when generate is
        set; otherwise a missing fingerprint is None.
        """
        fingerprint = self._fingerprint()
        if fingerprint is None and generate:
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
        if fingerprint is None:
            return None
        headers = cast("dict[str, str]", fingerprint.get("headers", {}))
        return curl.Identity(headers["user-agent"], headers["accept-language"])

    def jar(self, until: float) -> list[jar.Cookie]:
        """The cookies of the browser's own profile, under the profile lock.

        A killed session's injected cookies are purged first, and no other
        fetch's session runs meanwhile, so only the browser's own are read.
        """
        if not (self.profile / jar.DB_NAME).exists():
            return []
        lock = self._lock(until, JAR_LOCK_SECONDS)
        try:
            self._recover()
            return self._own_jar()
        finally:
            os.close(lock)

    def _own_jar(self) -> list[jar.Cookie]:
        """The profile's cookies from a consistent copy; the caller holds the lock."""
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
            now = jar.now_ms()
            deleted = [c for c in received if c.expiry_ms <= now]
            forget(self.profile / jar.DB_NAME, deleted)
            cookies = injection(self._own_jar(), librewolf, received, url, now)
            journal = [
                {"name": c.name, "host": c.host, "path": c.path, "digest": digest(c.value)}
                for c in cookies
            ]
            journal_path = self.state / JOURNAL
            write_private(journal_path, json.dumps(journal).encode())
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
        """Run session.py as init of a user, mount, network and PID namespace.

        The namespace's init dies with this process (PR_SET_PDEATHSIG on
        unshare, --kill-child on init), and the kernel then kills everything
        in it, Xvfb and the browser included, on any exit path. pasta, which
        connects the namespace, dies with this process too.
        """
        seconds = until - self.clock()
        if seconds <= 1:
            msg = "no time was left for the browser"
            raise BrowserError(msg)
        request_path = self.workdir / "session.json"
        result_path = self.workdir / "result.json"
        for stale in (result_path, self.workdir / NETNS_READY, self.workdir / NETWORK_READY):
            stale.unlink(missing_ok=True)
        write_private(
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
            "--net",
            "--pid",
            "--fork",
            "--kill-child",
            "--mount-proc",
            "--",
            self.tools.session,
            str(request_path),
        ]
        log = self.workdir / "session.log"
        pasta: subprocess.Popen[bytes] | None = None
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
            pasta = self._connect(process, until)
            process.wait(timeout=max(until - self.clock(), 1.0))
        except subprocess.TimeoutExpired:
            msg = f"the browser took longer than {seconds:.0f} s"
            raise BrowserError(msg) from None
        finally:
            for child in (process, pasta):
                if child is not None and child.poll() is None:
                    child.kill()
                if child is not None:
                    child.wait()
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

    def _connect(
        self, session: subprocess.Popen[bytes], until: float
    ) -> subprocess.Popen[bytes] | None:
        """Give the session's network namespace pasta's connectivity, then tell it so.

        None when the session ended before its namespace was ready; its own
        result says why.
        """
        give_up = min(until, self.clock() + NETWORK_SECONDS)
        while not (self.workdir / NETNS_READY).exists():
            if session.poll() is not None:
                return None
            if self.clock() >= give_up:
                msg = "the browser's namespace did not start"
                raise BrowserError(msg)
            time.sleep(_POLL_SECONDS)
        pid_file = self.workdir / "pasta.pid"
        pid_file.unlink(missing_ok=True)
        pasta_log = self.workdir / "pasta.log"
        with pasta_log.open("wb") as sink:
            pasta = subprocess.Popen(
                [self.tools.pasta, *PASTA_ARGS, "--pid", str(pid_file), str(session.pid)],
                stdin=subprocess.DEVNULL,
                stdout=sink,
                stderr=subprocess.STDOUT,
                env=self._environment(),
                cwd=self.workdir,
                preexec_fn=_die_with_parent,  # noqa: PLW1509 - prctl only, before exec
            )
        while not (pid_file.exists() and pid_file.stat().st_size):
            if pasta.poll() is not None or session.poll() is not None or self.clock() >= give_up:
                if pasta.poll() is None:
                    pasta.kill()
                pasta.wait()
                tail = pasta_log.read_text(errors="replace").strip().splitlines()[-1:] or [""]
                msg = f"the browser's network could not be set up: {tail[0][:200]}"
                raise BrowserError(msg.strip(": "))
            time.sleep(_POLL_SECONDS)
        write_private(self.workdir / NETWORK_READY, b"")
        return pasta
