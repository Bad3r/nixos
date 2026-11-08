# Copyright (c) 2026 Bad3r
"""Camoufox headed on a private Xvfb display, run as init of browser.py's namespace.

argv: the request file browser.py wrote. The result goes to result.json in the
work directory, the page to page.html or page.body beside it. A login opens
its window on the user's display instead, whose socket alone is bound in.

The namespace has its own network, which browser.py connects with pasta once
netns.ready appears; network.ready answers it.
"""

from __future__ import annotations

import contextlib
import ctypes
import http.server
import itertools
import json
import os
import secrets
import select
import shutil
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING, Any, cast, override
from urllib.parse import unquote, urlsplit

from browser_fetch import browser, challenge, curl, tools, urls

if TYPE_CHECKING:
    from collections.abc import Mapping

    from playwright.sync_api import BrowserContext, Page, Playwright, Request, Response

# The identity drawn once per browser release, by Camoufox's own launcher.
# Linux is the host's OS: on Xvfb's software rendering Camoufox then needs no
# canvas noise and reads as stock Firefox (README, "Canvas").
FINGERPRINT_OPTIONS: dict[str, Any] = {"os": "linux", "locale": "en-US", "humanize": True}
START_SECONDS = 60
LOAD_SECONDS = 60
SETTLE_SECONDS = 30
# Kept back from the session's deadline for closing the browser, which
# flushes the cookies it set to the profile (CookiePersistentStorage::Close).
CLOSE_SECONDS = 10
# How long Camoufox may take to install the guard addon after launch.
GUARD_SECONDS = 30
# How often a login looks for its windows being closed.
LOGIN_POLL_MS = 1000
POLL_SECONDS = 0.5
STABLE_POLLS = 2
STABLE_POLLS_SPARSE = 6
XVFB_SECONDS = 30
# Camoufox's virtual display (virtdisplay.py): a 1x1 root window, which no
# page can observe, and software GL.
XVFB_ARGS = (
    "-screen", "0", "1x1x24", "-ac", "-nolisten", "tcp",
    "-extension", "RENDER", "+extension", "GLX", "-extension", "COMPOSITE",
    "-extension", "XVideo", "-extension", "XVideo-MotionCompensation",
    "-extension", "XINERAMA", "-fp", "built-ins", "-nocursor", "-br",
)  # fmt: skip
MESA_EGL = "/run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json"
_MS_NOSUID = 2
_MS_NODEV = 4
_MS_BIND = 4096
_MS_REC = 16384
_PR_CAP_AMBIENT = 47
_PR_CAP_AMBIENT_CLEAR_ALL = 4
# curl's proxy schemes (lib/peer.c, Curl_scheme_to_proxytype) as Playwright's
# Firefox takes them, with the port curl connects to when the URL names none
# (the scheme's defport, lib/protocol.c). Firefox has a SOCKS proxy resolve
# names (Juggler's TRANSPARENT_PROXY_RESOLVES_HOST), as curl's socks5h and
# socks4a do; the egress is the proxy's either way.
_PROXY_SCHEMES = {
    "http": ("http", 80),
    "https": ("https", 443),
    "socks": ("socks4", 1080),
    "socks4": ("socks4", 1080),
    "socks4a": ("socks4", 1080),
    "socks5": ("socks5", 1080),
    "socks5h": ("socks5", 1080),
}
_STATE = """
(markers) => {
  const html = document.documentElement ? document.documentElement.outerHTML : "";
  const nav = performance.getEntriesByType("navigation")[0];
  return {
    ready: document.readyState,
    size: html.length,
    text: document.body ? document.body.innerText.trim().length : 0,
    challenge: markers.some((m) => html.includes(m)) || document.title === "Just a moment...",
    status: nav && nav.responseStatus ? nav.responseStatus : 0,
    type: document.contentType || "",
    uri: document.documentURI,
  };
}
"""
# Firefox's own error pages. The page keeps the URL it failed to load, and
# the document, which never completes its load, is the error page.
_ERROR_PAGES = ("about:neterror", "about:certerror")
# The error pages Firefox puts up for a 4xx or a 5xx document with an empty
# body (nsDocumentOpenInfo, browser.http.blank_page_with_error_response.enabled
# off): the response came, with nothing to show.
_EMPTY_ERROR_RESPONSES = frozenset({"httpErrorPage", "serverError"})
_HTTP_ERROR = 400
_SOURCE = """
() => {
  const d = document.doctype;
  const doctype = d ? "<!DOCTYPE " + d.name + ">" : "";
  return doctype + document.documentElement.outerHTML;
}
"""


class SessionError(Exception):
    """The session could not finish."""


@dataclass
class Policy:
    """WebFetch's redirect policy for top-level documents, answered for the guard addon.

    URLs are compared in canonical form (urls.canonical): the browser asks
    about the URL it requests, which may be spelled other than the target.
    environ holds curl's proxy variables, which choose the browser's proxy.
    """

    target: str
    token: str
    environ: Mapping[str, str] = field(default_factory=dict[str, str])
    approved: set[str] = field(default_factory=set[str])
    blocked: dict[str, Any] | None = None
    lock: threading.Lock = field(default_factory=threading.Lock)
    # Set once the guard's listeners are in place, before any navigation.
    ready: threading.Event = field(default_factory=threading.Event)

    def check(self, kind: str, origin: str, to: str, status: int) -> bool:
        """Whether the document request may go out; the first refusal is kept."""
        if kind == "ready":
            self.ready.set()
            return True
        with self.lock:
            if self.blocked is not None:
                return False
            if kind == "redirect":
                allow = self.follows(origin, to)
            else:
                allow = self.may_start(to) or (bool(origin) and self.follows(origin, to))
            if allow:
                self.approved.add(urls.canonical(to))
            else:
                self.block(origin or self.target, to, status)
            return allow

    def follows(self, origin: str, to: str) -> bool:
        """Whether WebFetch follows origin to `to`, which curl reaches as it reaches the target.

        The browser has one proxy, curl's for the target: a host curl routes
        otherwise, such as a www. twin no_proxy names alone, is not followed.
        """
        if not urls.redirect_allowed(origin, to):
            return False
        try:
            return curl.proxy(urls.request_host(to), self.environ) == curl.proxy(
                urls.request_host(self.target), self.environ
            )
        except urls.UrlError:
            return False

    def may_start(self, url: str) -> bool:
        """Whether a navigation that no page started may load url."""
        wanted = urls.canonical(url)
        return wanted in self.approved or wanted == urls.canonical(self.target)

    def block(self, origin: str, target: str, status: int) -> None:
        """Keep the first refused hop."""
        if self.blocked is None:
            self.blocked = {"origin": origin, "target": target, "status": status}


def policy_server(policy: Policy) -> http.server.ThreadingHTTPServer:
    """Serve the policy on a loopback port, to callers holding its token."""

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_POST(self) -> None:
            length = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(min(length, 1 << 16))
            allow = False
            if secrets.compare_digest(self.headers.get("X-Token", ""), policy.token):
                with contextlib.suppress(ValueError, KeyError, TypeError):
                    ask = cast("dict[str, Any]", json.loads(body))
                    allow = policy.check(
                        str(ask["kind"]), str(ask["from"]), str(ask["to"]), int(ask["status"])
                    )
            reply = json.dumps({"allow": allow}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(reply)))
            self.end_headers()
            self.wfile.write(reply)

        @override
        def log_message(self, format: str, *args: Any) -> None:
            return

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def _headers_server() -> tuple[http.server.HTTPServer, dict[str, str]]:
    """A loopback page that records the request headers the browser sends."""
    seen: dict[str, str] = {}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            seen.update({k.lower(): v for k, v in self.headers.items()})
            reply = b"<!DOCTYPE html><title>ok</title>"
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(reply)))
            self.end_headers()
            self.wfile.write(reply)

        @override
        def log_message(self, format: str, *args: Any) -> None:
            return

    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, seen


def private_tmp(keep: list[Path], files: list[Path] | None = None) -> None:
    """Give the namespace its own /tmp, so Xvfb's socket and lock die with it.

    The directories in keep and the files in files, such as an X display's
    socket, that lie under the old /tmp are bound back in, and nothing else.
    """
    libc = ctypes.CDLL(None, use_errno=True)
    old = os.open("/tmp", os.O_PATH | os.O_DIRECTORY)  # noqa: S108 - the mount point
    if libc.mount(b"tmpfs", b"/tmp", b"tmpfs", _MS_NOSUID | _MS_NODEV, b"mode=1777") != 0:
        raise OSError(ctypes.get_errno(), "mounting a private /tmp failed")
    for path, is_file in [*((k, False) for k in keep), *((f, True) for f in files or [])]:
        if path.parts[:2] != ("/", "tmp"):
            continue
        relative = Path(*path.parts[2:])
        if is_file:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()
        else:
            path.mkdir(parents=True, exist_ok=True)
        source = f"/proc/self/fd/{old}/{relative}".encode()
        if libc.mount(source, str(path).encode(), None, _MS_BIND | _MS_REC, None) != 0:
            raise OSError(ctypes.get_errno(), f"binding {path} into the private /tmp failed")
    os.close(old)


def await_network(workdir: Path, until: float) -> None:
    """Report the namespace to browser.py and wait until pasta has connected it."""
    browser.write_private(workdir / browser.NETNS_READY, b"")
    give_up = min(until, time.monotonic() + browser.NETWORK_SECONDS)
    while not (workdir / browser.NETWORK_READY).exists():
        if time.monotonic() >= give_up:
            msg = "the namespace's network was never connected"
            raise SessionError(msg)
        time.sleep(0.05)


def loopback_up() -> None:
    """Bring the namespace's loopback up, for the session's own listeners."""
    _ip(["link", "set", "lo", "up"])


def _ip(args: list[str], stdin: str = "") -> None:
    ran = subprocess.run(
        [tools.IP, *args],
        input=stdin,
        capture_output=True,
        text=True,
        env={"PATH": "/var/empty"},
        timeout=10,
        check=False,
    )
    if ran.returncode != 0:
        msg = f"ip {' '.join(args)} failed: {ran.stderr.strip()[:200]}"
        raise SessionError(msg)


def drop_capabilities() -> None:
    """Drop the ambient capabilities unshare --keep-caps granted, so nothing started holds them."""
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(_PR_CAP_AMBIENT, _PR_CAP_AMBIENT_CLEAR_ALL, 0, 0, 0) != 0:
        raise OSError(ctypes.get_errno(), "dropping the ambient capabilities failed")


def start_xvfb(until: float) -> tuple[subprocess.Popen[bytes], str]:
    """Start Xvfb and return it with the display it chose, one no other server holds."""
    read_end, write_end = os.pipe()
    process = subprocess.Popen(
        [tools.XVFB, "-displayfd", str(write_end), *XVFB_ARGS],
        pass_fds=(write_end,),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env={
            "PATH": "/var/empty",
            "__GLX_VENDOR_LIBRARY_NAME": "mesa",
            "LIBGL_ALWAYS_SOFTWARE": "1",
        },
    )
    os.close(write_end)
    reported = b""
    try:
        while b"\n" not in reported:
            left = min(until, time.monotonic() + XVFB_SECONDS) - time.monotonic()
            if left <= 0 or not select.select([read_end], [], [], left)[0]:
                msg = "Xvfb did not report a display"
                raise SessionError(msg)
            chunk = os.read(read_end, 64)
            if not chunk:
                msg = f"Xvfb exited {process.poll()} before reporting a display"
                raise SessionError(msg)
            reported += chunk
    finally:
        os.close(read_end)
    return process, f":{int(reported.strip())}"


def browser_env(home: Path, display: str) -> dict[str, str]:
    """The browser's environment: the private display, and nothing of the user's session."""
    env = {
        "HOME": str(home),
        "XDG_CACHE_HOME": str(home / ".cache"),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_DATA_HOME": str(home / ".local/share"),
        "TMPDIR": "/tmp",  # noqa: S108 - the namespace's own
        "PATH": "/var/empty",
        "DISPLAY": display,
        "GDK_BACKEND": "x11",
        "MOZ_ENABLE_WAYLAND": "0",
        "MOZ_CRASHREPORTER_DISABLE": "1",
        # Software GL, as on Camoufox's Xvfb; the host GPU stays out of it.
        "__EGL_VENDOR_LIBRARY_FILENAMES": MESA_EGL,
        "__GLX_VENDOR_LIBRARY_NAME": "mesa",
        "LIBGL_ALWAYS_SOFTWARE": "1",
    }
    for key in ("LANG", "LC_ALL", "TZ"):
        if key in os.environ:
            env[key] = os.environ[key]
    return env


def proxy_settings(url: str, environ: Mapping[str, str]) -> dict[str, str] | None:
    """The proxy curl uses for url, for Playwright; None when curl goes direct.

    curl's no_proxy is decided here and never handed over: Juggler reads a
    bypass entry as a bare suffix of the host, unlike curl.
    """
    server = curl.proxy(urls.request_host(url), environ)
    if server is None:
        return None
    parts = urlsplit(server if "://" in server else f"http://{server}")
    if parts.scheme not in _PROXY_SCHEMES:
        msg = f"curl takes no {parts.scheme}:// proxy, so the browser takes none either"
        raise SessionError(msg)
    scheme, default_port = _PROXY_SCHEMES[parts.scheme]
    try:
        port = default_port if parts.port is None else parts.port
    except ValueError:
        msg = "the proxy's port is not a port number"
        raise SessionError(msg) from None
    host = parts.hostname or ""
    if not host:
        msg = "the proxy names no host"
        raise SessionError(msg)
    if ":" in host:
        # Playwright passes Firefox the host as the URL spells it, in
        # brackets, and Gecko takes that for an unresolvable name.
        msg = "the browser cannot use a proxy at an IPv6 address"
        raise SessionError(msg)
    settings = {"server": f"{scheme}://{host}:{port}"}
    if parts.username is None and parts.password is None:
        return settings
    if scheme.startswith("socks"):
        msg = "the browser cannot authenticate to a SOCKS proxy"
        raise SessionError(msg)
    # Decoded, as curl's parse_proxy reads them (CURLU_URLDECODE).
    try:
        settings["username"] = unquote(parts.username or "", errors="strict")
        settings["password"] = unquote(parts.password or "", errors="strict")
    except UnicodeDecodeError:
        msg = "the proxy's credentials are not UTF-8"
        raise SessionError(msg) from None
    return settings


def _generate(state: Path, env: dict[str, str], until: float) -> None:
    """Draw the identity with Camoufox's launcher and record the headers it sends."""
    from camoufox.utils import launch_options  # noqa: PLC0415 - after HOME is set
    from playwright.sync_api import sync_playwright  # noqa: PLC0415

    options = launch_options(
        **FINGERPRINT_OPTIONS,
        executable_path=tools.CAMOUFOX,
        headless=False,
        virtual_display=env["DISPLAY"],
        env=dict(env),
    )
    blob = "".join(
        cast("str", options["env"][key])
        for key in sorted(
            (k for k in options["env"] if k.startswith("CAMOU_CONFIG_")),
            key=lambda k: int(k.rsplit("_", 1)[1]),
        )
    )
    config = cast("dict[str, Any]", json.loads(blob))
    prefs = cast("dict[str, Any]", options["firefox_user_prefs"])
    server, seen = _headers_server()
    try:
        with sync_playwright() as playwright:
            browser = playwright.firefox.launch(
                executable_path=tools.CAMOUFOX,
                headless=False,
                env=cast("dict[str, str | float | bool]", _launch_env(env, config, prefs)),
                firefox_user_prefs=prefs,
                timeout=_ms(until, START_SECONDS),
            )
            try:
                page = browser.new_page(no_viewport=True)
                page.goto(f"http://127.0.0.1:{server.server_port}/", timeout=_ms(until, 30))
            finally:
                browser.close()
    finally:
        server.shutdown()
        server.server_close()
    if not seen.get("user-agent") or not seen.get("accept-language"):
        msg = "the browser sent no User-Agent or Accept-Language"
        raise SessionError(msg)
    fingerprint = {
        "browser": tools.CAMOUFOX_VERSION,
        "options": FINGERPRINT_OPTIONS,
        "os": "lin",
        "config": config,
        "prefs": prefs,
        "headers": {
            "user-agent": seen["user-agent"],
            "accept-language": seen["accept-language"],
        },
    }
    _write_json(state / "fingerprint.json", fingerprint)


def _launch_env(
    env: dict[str, str], config: dict[str, Any], prefs: dict[str, Any]
) -> dict[str, str]:
    """The browser's environment: the identity as CAMOU_CONFIG, prefs as CAMOU_PREFS."""
    from camoufox.utils import get_env_vars, get_pref_env_vars  # noqa: PLC0415

    camou = get_env_vars(config, "lin", path=Path(tools.CAMOUFOX))
    return {**env, **{k: str(v) for k, v in camou.items()}, **get_pref_env_vars(prefs)}


def _ms(until: float, cap: float) -> float:
    return max(1.0, min(cap, until - time.monotonic())) * 1000


def _write_json(path: Path, data: object) -> None:
    browser.write_private(path, json.dumps(data).encode())


def _guard(policy: Policy, port: int) -> Path:
    """The guard addon, copied into the private /tmp with its port and token."""
    addon = Path("/tmp/browser-fetch-guard")  # noqa: S108 - the namespace's own
    shutil.copytree(Path(__file__).parent / "guard", addon)
    (addon / "config.js").write_text(
        "globalThis.BROWSER_FETCH = " + json.dumps({"port": port, "token": policy.token}) + ";\n"
    )
    return addon


def _page_state(page: Page) -> dict[str, Any]:
    """The document's load state, or {} while a navigation replaces it."""
    try:
        return cast("dict[str, Any]", page.evaluate(_STATE, list(challenge.BODY_MARKERS)))
    except Exception:  # noqa: BLE001 - a navigation replaced the document mid-poll
        return {}


def _settle(page: Page, policy: Policy, until: float) -> dict[str, Any]:
    """Wait for the load, a challenge to clear and the DOM to hold still, within until."""
    previous_size = -1
    stable = 0
    state: dict[str, Any] = {}
    while policy.blocked is None:
        state = _page_state(page)
        if not state:
            previous_size, stable = -1, 0
        else:
            stable = stable + 1 if state["size"] == previous_size else 0
            previous_size = state["size"]
            if str(state.get("uri") or "").startswith(_ERROR_PAGES):
                break
            quiet = state["ready"] == "complete" and not state["challenge"]
            needed = STABLE_POLLS if state["text"] >= challenge.SHELL_TEXT else STABLE_POLLS_SPARSE
            if quiet and stable >= needed:
                break
        if time.monotonic() >= until:
            break
        time.sleep(POLL_SECONDS)
    return state


def _launch(  # noqa: PLR0913 - what one launch of the persistent profile takes
    playwright: Playwright,
    request: dict[str, Any],
    *,
    state: Path,
    env: dict[str, str],
    until: float,
    addons: list[str],
) -> BrowserContext:
    """Start the browser on the request's profile with the fingerprint, as a fetch does.

    addons go after the ones the build bundles; curl's proxy for the
    request's URL is the browser's.
    """
    fingerprint = cast("dict[str, Any]", json.loads((state / "fingerprint.json").read_text()))
    config = dict(cast("dict[str, Any]", fingerprint["config"]))
    # The addons the build bundles, from this build: a store path may move.
    bundled = Path(tools.CAMOUFOX).parent / "addons"
    config["addons"] = [*(str(bundled / Path(a).name) for a in config.get("addons", [])), *addons]
    # Neither is visible to a page. The JSON viewer off leaves the JSON as the
    # document; no disk cache keeps a page fetched with the profile's cookies.
    prefs = {
        **cast("dict[str, Any]", fingerprint["prefs"]),
        "devtools.jsonview.enabled": False,
        "browser.cache.disk.enable": False,
    }
    return playwright.firefox.launch_persistent_context(
        user_data_dir=str(request["profile"]),
        executable_path=tools.CAMOUFOX,
        headless=False,
        env=cast("dict[str, str | float | bool]", _launch_env(env, config, prefs)),
        firefox_user_prefs=prefs,
        no_viewport=True,
        color_scheme="null",
        reduced_motion="null",
        forced_colors="null",
        contrast="null",
        proxy=proxy_settings(str(request["url"]), os.environ),  # type: ignore[arg-type]
        timeout=_ms(until, START_SECONDS),
    )


def _close(context: BrowserContext) -> list[str]:
    """Close the browser, which writes the cookies it holds to the profile; warn if it fails."""
    try:
        context.close()
    except Exception as error:  # noqa: BLE001 - what the session did still stands
        first = str(error).splitlines()[0][:200] if str(error) else type(error).__name__
        return [f"the browser did not close cleanly, so cookies it set may be lost: {first}"]
    return []


def _render(
    request: dict[str, Any], state: Path, env: dict[str, str], until: float
) -> dict[str, Any]:
    from playwright.sync_api import sync_playwright  # noqa: PLC0415

    url = str(request["url"])
    policy = Policy(target=url, token=secrets.token_urlsafe(24), environ=os.environ)
    server = policy_server(policy)
    document: list[Response] = []
    try:
        with sync_playwright() as playwright:
            guard = str(_guard(policy, server.server_port))
            context = _launch(
                playwright, request, state=state, env=env, until=until, addons=[guard]
            )
            try:
                result = drive(context, request, policy, document, until - CLOSE_SECONDS)
            except BaseException:
                with contextlib.suppress(Exception):
                    context.close()
                raise
            warnings = _close(context)
            if warnings:
                result["warnings"] = warnings
            return result
    finally:
        server.shutdown()
        server.server_close()


def _login(
    request: dict[str, Any], state: Path, env: dict[str, str], until: float
) -> dict[str, Any]:
    """Open the request's URL in a window and wait until the user closes every one.

    No guard limits where the user goes. At until the browser is closed for
    them. Either way it closes through Playwright, as a render's does, so
    the cookies it holds reach the profile.
    """
    from playwright.sync_api import sync_playwright  # noqa: PLC0415

    with sync_playwright() as playwright:
        context = _launch(playwright, request, state=state, env=env, until=until, addons=[])
        try:
            page = context.pages[0] if context.pages else context.new_page()
            with contextlib.suppress(Exception):
                # A page that fails to load still leaves the window to the user.
                page.goto(str(request["url"]), wait_until="commit", timeout=_ms(until, 30))
            closed = await_windows_closed(context, until - CLOSE_SECONDS)
        except BaseException:
            with contextlib.suppress(Exception):
                context.close()
            raise
        warnings = _close(context)
    if not closed:
        warnings.insert(0, f"the login took longer than {browser.LOGIN_SECONDS // 60} minutes")
    return {"closed": closed, "warnings": warnings}


def await_windows_closed(context: BrowserContext, until: float) -> bool:
    """Wait until the browser has no page left, or until passes; whether it has none.

    Waiting on a page's close event keeps Playwright's connection serviced,
    so a window the user closes is seen.
    """
    from playwright.sync_api import TimeoutError as PlaywrightTimeoutError  # noqa: PLC0415

    while context.pages:
        left = until - time.monotonic()
        if left <= 0:
            return False
        try:
            context.pages[0].wait_for_event("close", timeout=min(LOGIN_POLL_MS, left * 1000))
        except PlaywrightTimeoutError:
            continue
    return True


def drive(
    context: BrowserContext,
    request: dict[str, Any],
    policy: Policy,
    document: list[Response],
    until: float,
) -> dict[str, Any]:
    """Load the target once the guard is ready, and write what the page became."""
    give_up = min(until, time.monotonic() + GUARD_SECONDS)
    if not policy.ready.wait(timeout=max(0.0, give_up - time.monotonic())):
        msg = "the browser's request guard did not start"
        raise SessionError(msg)
    cookies = cast("list[dict[str, Any]]", request.get("cookies", []))
    if cookies:
        context.add_cookies(cookies)  # type: ignore[arg-type]
    added = len(cookies)
    page = context.pages[0] if context.pages else context.new_page()

    def keep(response: Response) -> None:
        if response.request.is_navigation_request() and response.frame == page.main_frame:
            document.append(response)

    page.on("response", keep)
    failure: str | None = None
    try:
        page.goto(policy.target, wait_until="commit", timeout=_ms(until, LOAD_SECONDS))
    except Exception as error:  # noqa: BLE001 - a later allowed navigation may still commit
        failure = str(error).splitlines()[0][:200] if str(error) else type(error).__name__
    if policy.blocked is not None:
        return {"blocked": _blocked(policy.blocked, document), "cookies": added}
    state = _settle(page, policy, min(until, time.monotonic() + SETTLE_SECONDS))
    _verify(page, policy, document)
    if policy.blocked is not None:
        return {"blocked": _blocked(policy.blocked, document), "cookies": added}
    result = _document(page, Path(str(request["workdir"])), state, document, failure)
    result["cookies"] = added
    return result


def _blocked(blocked: dict[str, Any], document: list[Response]) -> dict[str, Any]:
    """The refused hop; a script's navigation has no status and takes its document's.

    That is the status of the last main-document response: a refused
    navigation never replaces the document it leaves.
    """
    if blocked["status"]:
        return blocked
    if not document:
        msg = (
            f"the browser refused a navigation to {blocked['target']} from a page no response made"
        )
        raise SessionError(msg)
    return {**blocked, "status": document[-1].status}


def _document(
    page: Page,
    workdir: Path,
    state: dict[str, Any],
    document: list[Response],
    failure: str | None,
) -> dict[str, Any]:
    """Write the document the page ended on, or fail when it has none.

    An error page in place of an empty 4xx or 5xx document stands for that
    response, with its status and no body; any other error page is a failure.
    """
    final = page.url
    shown = _shown(page, state)
    error_page = next((uri for uri in (shown, final) if uri.startswith(_ERROR_PAGES)), None)
    if error_page is not None:
        query = error_page.split("?", 1)[-1]
        code = dict(p.split("=", 1) for p in query.split("&") if "=" in p).get("e", "")
        sent = document[-1] if document else None
        if code in _EMPTY_ERROR_RESPONSES and sent is not None and sent.status >= _HTTP_ERROR:
            (workdir / "page.body").write_bytes(b"")
            content_type = sent.headers.get("content-type", "")
            return {"url": final, "status": sent.status, "contentType": content_type}
        msg = f"the browser could not load the page ({code or 'network error'})"
        raise SessionError(msg)
    if not document and final in {"", "about:blank"}:
        msg = f"the browser loaded no document ({failure or 'no navigation committed'})"
        raise SessionError(msg)
    response = document[-1] if document else None
    header = response.headers.get("content-type", "") if response is not None else ""
    content_type = header or str(state.get("type") or "")
    status = int(state.get("status") or 0) or (response.status if response is not None else 200)
    result: dict[str, Any] = {"url": final, "status": status, "contentType": content_type}
    if response is None or "html" in content_type.lower():
        (workdir / "page.html").write_text(
            str(page.evaluate(_SOURCE)), encoding="utf-8", errors="surrogatepass"
        )
        result["html"] = True
    else:
        (workdir / "page.body").write_bytes(response.body())
    return result


def _shown(page: Page, state: dict[str, Any]) -> str:
    """The URI of the document the page shows, which an error page does not share with page.url."""
    if state.get("uri"):
        return str(state["uri"])
    try:
        return str(page.evaluate("() => document.documentURI"))
    except Exception:  # noqa: BLE001 - no document to ask; page.url stands
        return ""


def _verify(page: Page, policy: Policy, document: list[Response]) -> None:
    """Hold the main document's redirect chain and final URL to the policy as well.

    The guard stops a hop before it is sent; this catches one it never saw.
    """
    hops: list[Request] = []
    if document:
        request: Request | None = document[-1].request
        while request is not None:
            hops.insert(0, request)
            request = request.redirected_from
    if hops and not policy.may_start(hops[0].url):
        policy.block(policy.target, hops[0].url, 0)
        return
    for before, after in itertools.pairwise(hops):
        if not policy.follows(before.url, after.url):
            sent = before.response()
            policy.block(before.url, after.url, sent.status if sent is not None else 0)
            return
    final = page.url
    if final.startswith(("about:", "data:")) or policy.blocked is not None:
        return
    landed = hops[-1].url if hops else policy.target
    if not policy.follows(landed, final) and urls.canonical(final) not in policy.approved:
        policy.block(landed, final, 0)


def main(argv: list[str] | None = None) -> int:
    """Run one session; the exit status is 0 once result.json is written."""
    args = sys.argv[1:] if argv is None else argv
    request_path = Path(args[0])
    request = cast("dict[str, Any]", json.loads(request_path.read_text()))
    workdir = Path(str(request["workdir"]))
    state = Path(str(request["state"]))
    until = time.monotonic() + float(request["seconds"])
    login = request["mode"] == "login"
    server: subprocess.Popen[bytes] | None = None
    try:
        private_tmp([workdir, state], [Path(str(request["socket"]))] if login else [])
        await_network(workdir, until)
        loopback_up()
        drop_capabilities()
        if login:
            display = str(request["display"])
        else:
            server, display = start_xvfb(until)
        home = state / "home"
        home.mkdir(mode=0o700, exist_ok=True)
        env = browser_env(home, display)
        if login:
            env["XAUTHORITY"] = str(request["xauthority"])
        # Camoufox's launcher writes its fontconfig under its cache directory.
        os.environ.update(HOME=env["HOME"], XDG_CACHE_HOME=env["XDG_CACHE_HOME"], TMPDIR="/tmp")  # noqa: S108
        if request["mode"] == "generate":
            _generate(state, env, until)
            result: dict[str, Any] = {"generated": True}
        elif login:
            result = _login(request, state, env, until)
        else:
            result = _render(request, state, env, until)
    except Exception as error:  # noqa: BLE001 - reported to browser.py in one line
        first = str(error).splitlines()[0][:200] if str(error) else ""
        result = {"error": f"{type(error).__name__}: {first}"}
    finally:
        if server is not None:
            server.terminate()
            with contextlib.suppress(subprocess.TimeoutExpired):
                server.wait(timeout=5)
    _write_json(workdir / "result.json", result)
    return 0


if __name__ == "__main__":
    sys.exit(main())
