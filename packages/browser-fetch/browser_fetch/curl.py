# Copyright (c) 2026 Bad3r
"""One GET request through curl-impersonate with a Firefox profile."""

from __future__ import annotations

import ipaddress
import json
import os
import subprocess
from dataclasses import dataclass
from typing import TYPE_CHECKING

from browser_fetch import cookies as jar
from browser_fetch.redact import Redactor

if TYPE_CHECKING:
    from collections.abc import Mapping
    from pathlib import Path

    from browser_fetch.urls import Pinned

# curl-impersonate's target: TLS, HTTP/2 and the headers, as upstream ships it.
IMPERSONATE = "firefox155"
MAX_BYTES = 10 * 1024 * 1024
# Bounds DNS (curl-impersonate 2.3 waits for an HTTPS record), TCP and TLS.
CONNECT_SECONDS = 30
_REASONS = {
    6: "the host name did not resolve",
    7: "the connection was refused or failed",
    28: "the request timed out",
    35: "the TLS handshake failed",
    47: "curl followed too many redirects",
    52: "the server sent no response",
    56: "the connection broke while receiving",
    60: "the server's TLS certificate was not trusted",
    63: f"the response is larger than {MAX_BYTES} bytes",
}
# The variables curl reads a proxy for an https URL from, first one set wins
# (lib/proxy.c); an empty one counts as unset.
PROXY_VARIABLES = ("https_proxy", "HTTPS_PROXY", "all_proxy", "ALL_PROXY")


@dataclass(frozen=True)
class Identity:
    """The headers that name the browser: Camoufox's, so its cookies hold on curl too."""

    user_agent: str
    accept_language: str


class TransportError(Exception):
    """The request produced no HTTP response."""


@dataclass(frozen=True)
class Response:
    """An HTTP response: status, headers by lowercase name, and the body file."""

    status: int
    headers: dict[str, list[str]]
    body: Path

    def header(self, name: str) -> str | None:
        """Return the last value of a header, or None."""
        values = self.headers.get(name.lower())
        return values[-1] if values else None


def _quote(value: str) -> str:
    """Quote a value for a curl config file."""
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def _write_private(path: Path, text: str) -> None:
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as handle:
        handle.write(text)


def _header_lines(identity: Identity | None, cookie_header: str) -> str:
    """The browser's identity and the cookies, as curl config header lines.

    curl-impersonate replaces a profile header in place, so the order stays
    the profile's; every other header is the profile's own.
    """
    headers: list[str] = []
    if identity is not None:
        headers += [
            f"User-Agent: {identity.user_agent}",
            f"Accept-Language: {identity.accept_language}",
        ]
    if cookie_header:
        # A header line, not curl's cookie option: that reads a value with no
        # "=" as a file name, while Firefox sends a nameless cookie bare.
        headers.append(f"Cookie: {cookie_header}")
    return "".join(f"header = {_quote(line)}\n" for line in headers if not {"\r", "\n"} & set(line))


def _resolve_entry(pinned: Pinned) -> str:
    """Curl's --resolve entry: the URL's host and port to the checked addresses."""
    listed = ",".join(f"[{a}]" if ":" in a else a for a in pinned.addresses)
    return f"{pinned.host}:{pinned.port}:{listed}"


def proxy(environ: Mapping[str, str]) -> str | None:
    """The proxy curl uses for an https URL under environ, or None."""
    return next((environ[name] for name in PROXY_VARIABLES if environ.get(name)), None)


def _connected_elsewhere(remote: str, pinned: Pinned, environ: Mapping[str, str]) -> bool:
    # With a proxy, the proxy resolves the name and curl connects to the proxy.
    if not remote or proxy(environ) is not None:
        return False
    try:
        address = ipaddress.ip_address(remote)
    except ValueError:
        return True
    return address not in {ipaddress.ip_address(a.split("%", 1)[0]) for a in pinned.addresses}


def request(  # noqa: PLR0913 - keyword-only knobs of one request
    pinned: Pinned,
    *,
    cookies: list[jar.Cookie],
    identity: Identity | None,
    workdir: Path,
    name: str,
    curl: str,
    timeout: float,
) -> Response:
    """GET the pinned URL without following redirects; the body lands in workdir.

    curl connects only to the pinned addresses, so a second DNS answer
    cannot move the request. The Cookie header travels in a private config
    file, never in argv.
    """
    url = pinned.url
    config = workdir / f"{name}.conf"
    body = workdir / f"{name}.body"
    redactor = Redactor([cookie.value for cookie in cookies])
    _write_private(config, _header_lines(identity, jar.header(cookies)))
    argv = [
        curl,
        "--disable",
        "--impersonate",
        IMPERSONATE,
        "--compressed",
        "--silent",
        "--show-error",
        "--proto",
        "=https",
        "--connect-timeout",
        f"{max(min(CONNECT_SECONDS, timeout), 1.0):.0f}",
        "--max-time",
        f"{max(timeout, 1.0):.0f}",
        "--max-filesize",
        str(MAX_BYTES),
        "--resolve",
        _resolve_entry(pinned),
        "--config",
        str(config),
        "--output",
        str(body),
        "--write-out",
        "%{http_code}\n%{remote_ip}\n%{header_json}",
        "--",
        url,
    ]
    try:
        ran = subprocess.run(
            argv,
            capture_output=True,
            text=True,
            errors="replace",
            timeout=timeout + 10,
            check=False,
        )
    except subprocess.TimeoutExpired:
        msg = "the request timed out"
        raise TransportError(msg) from None
    finally:
        config.unlink(missing_ok=True)
    if ran.returncode != 0:
        reason = _REASONS.get(ran.returncode) or redactor.scrub(ran.stderr.strip())
        msg = f"request to {url} failed: {reason or f'curl exited {ran.returncode}'}"
        raise TransportError(msg)
    status_line, _, rest = ran.stdout.partition("\n")
    remote, _, header_json = rest.partition("\n")
    if _connected_elsewhere(remote.strip(), pinned, os.environ):
        msg = f"request to {url} reached {remote.strip()}, not the address it was checked at"
        raise TransportError(msg)
    try:
        status = int(status_line)
        raw: dict[str, list[str]] = json.loads(header_json or "{}")
    except ValueError:
        msg = f"request to {url} returned no readable status"
        raise TransportError(msg) from None
    if body.exists() and body.stat().st_size > MAX_BYTES:
        msg = f"request to {url} failed: {_REASONS[63]}"
        raise TransportError(msg)
    if not body.exists():
        body.write_bytes(b"")
    return Response(status, {key.lower(): value for key, value in raw.items()}, body)
