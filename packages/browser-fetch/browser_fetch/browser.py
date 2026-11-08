# Copyright (c) 2026 Bad3r
"""Camoufox with one persistent profile and identity, run by session.py in a namespace."""

from __future__ import annotations

import ctypes
import fcntl
import json
import os
import signal
import subprocess
import time
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any, cast

from browser_fetch import cookies as jar
from browser_fetch import curl

if TYPE_CHECKING:
    from collections.abc import Callable, Mapping
    from pathlib import Path

# Bounds of one fallback: waiting for another fetch's browser, then the
# session's own start, load and challenge wait, which session.py splits.
LOCK_SECONDS = 90
# A jar read or write waits this long for a session holding the profile,
# then goes on without it: it never stalls a fetch behind another one's render.
JAR_LOCK_SECONDS = 2
GENERATE_SECONDS = 90
FINGERPRINT = "fingerprint.json"
LOCK = "camoufox.lock"
PROFILE = "profile"
HOME = "home"
_PR_SET_PDEATHSIG = 1
_POLL_SECONDS = 0.1
_ENV_KEEP = ("LANG", "LC_ALL", "TZ", *curl.PROXY_VARIABLES, *curl.NO_PROXY_VARIABLES)
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
    # What the session could not do that the fetch should report.
    warnings: tuple[str, ...] = ()


def die_with_parent() -> None:
    """Have the kernel SIGKILL this process when its parent exits."""
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


def playwright_cookie(cookie: jar.Cookie) -> dict[str, Any]:
    """A cookie for Playwright's add_cookies, as a session cookie in Gecko's host form.

    Juggler stores SameSite=None as unset, which acts as None while
    network.cookie.sameSite.laxByDefault is off; neither is passed.
    """
    added: dict[str, Any] = {
        "name": cookie.name,
        "value": cookie.value,
        "domain": cookie.host,
        "path": cookie.path,
        "expires": -1,
        "httpOnly": cookie.http_only,
        "secure": cookie.secure,
    }
    if cookie.same_site == jar.SAME_SITE_STRICT:
        added["sameSite"] = "Strict"
    elif cookie.same_site == jar.SAME_SITE_LAX:
        added["sameSite"] = "Lax"
    return added


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
        headers = fingerprint.get("headers")
        if not (
            fingerprint.get("browser") == self.tools.camoufox_version
            and isinstance(headers, dict)
            and {"user-agent", "accept-language"} <= headers.keys()
        ):
            return None
        return fingerprint

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
        headers = cast("dict[str, str]", fingerprint["headers"])
        return curl.Identity(headers["user-agent"], headers["accept-language"])

    def jar(self, until: float) -> list[jar.Cookie]:
        """The cookies of the browser's profile, read under the profile lock.

        The lock waits only JAR_LOCK_SECONDS: a busy profile is the caller's
        to report, never a reason to wait out another fetch's render.
        """
        database = self.profile / jar.DB_NAME
        if not database.exists():
            return []
        lock = self._lock(until, JAR_LOCK_SECONDS)
        try:
            return jar.read(database)
        finally:
            os.close(lock)

    def store(self, cookies: jar.Jar, until: float) -> None:
        """Write the fetch's unsaved cookie changes into the profile, under the profile lock."""
        if not cookies.unsaved:
            return
        lock = self._lock(until, JAR_LOCK_SECONDS)
        try:
            self._store(cookies)
        finally:
            os.close(lock)

    def _store(self, cookies: jar.Jar) -> None:
        """Write the unsaved changes; the caller holds the lock, so no browser runs."""
        jar.store(self.profile / jar.DB_NAME, cookies.pending(), jar.now_us())
        cookies.unsaved.clear()

    def render(self, url: str, cookies: jar.Jar, until: float, *, keep: bool = True) -> Rendered:
        """Load url in the browser, which starts from curl's cookies.

        With keep, the browser runs on its persistent profile under the
        profile lock: the fetch's changes are written into it first, and the
        session cookies, which Gecko never stores, are added through
        Playwright. Without keep, a profile in the work directory, discarded
        with it, gets every live cookie the fetch received as a session
        cookie. Playwright adds to the unpartitioned jar only, so a
        partitioned cookie is not added.
        """
        now = jar.now_us() // 1000
        if not keep:
            handed = [c for c in cookies.received(now) if not c.partition]
            return self._rendered(self._session_for(url, self.workdir / PROFILE, handed, until))
        lock = self._lock(until)
        try:
            self._store(cookies)
            handed = [c for c in cookies.received(now) if c.session and not c.partition]
            result = self._session_for(url, self.profile, handed, until)
        finally:
            os.close(lock)
        return self._rendered(result)

    def _session_for(
        self, url: str, profile: Path, handed: list[jar.Cookie], until: float
    ) -> dict[str, Any]:
        return self._session(
            "render",
            {
                "url": url,
                "profile": str(profile),
                "cookies": [playwright_cookie(c) for c in handed],
            },
            until,
        )

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
            warnings=tuple(str(w) for w in cast("list[Any]", result.get("warnings") or [])),
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
                preexec_fn=die_with_parent,  # noqa: PLW1509 - prctl only, before exec
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
                preexec_fn=die_with_parent,  # noqa: PLW1509 - prctl only, before exec
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
