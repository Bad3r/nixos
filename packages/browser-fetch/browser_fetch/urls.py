# Copyright (c) 2026 Bad3r
"""URL checks and the redirect policy of Claude Code 2.1.319's WebFetch."""

from __future__ import annotations

import ipaddress
import re
from urllib.parse import SplitResult, quote, unquote, urlsplit, urlunsplit

import idna

MAX_URL_LENGTH = 2000
MAX_REDIRECTS = 10
REDIRECT_STATUSES = frozenset({301, 302, 303, 307, 308})
DEFAULT_PORTS = {"http": 80, "https": 443}


class UrlError(Exception):
    """The URL is not one WebFetch fetches."""


def _whatwg_ipv4(host: str) -> str | None:
    """Return the dotted address the URL standard reads a numeric host as.

    None when the last label is not a number, so the host is a name; a
    numeric host the standard rejects raises UrlError.
    """
    labels = host.split(".")
    if labels[-1] == "" and len(labels) > 1:
        labels.pop()
    last = labels[-1]
    if not (last.isdigit() or re.fullmatch(r"0[xX][0-9a-fA-F]*", last)):
        return None
    numbers: list[int] = []
    for label in labels:
        try:
            if label[:2].lower() == "0x":
                numbers.append(int(label[2:] or "0", 16))
            elif len(label) > 1 and label.startswith("0"):
                numbers.append(int(label[1:], 8))
            else:
                numbers.append(int(label, 10))
        except ValueError:
            msg = "Invalid URL"
            raise UrlError(msg) from None
    if len(numbers) > 4 or any(n > 255 for n in numbers[:-1]):  # noqa: PLR2004
        msg = "Invalid URL"
        raise UrlError(msg)
    if numbers[-1] >= 256 ** (5 - len(numbers)):
        msg = "Invalid URL"
        raise UrlError(msg)
    value = numbers[-1] + sum(n * 256 ** (3 - i) for i, n in enumerate(numbers[:-1]))
    return str(ipaddress.IPv4Address(value))


def _whatwg_ipv6(host: str) -> str:
    """Return an IPv6 literal as the URL standard serializes it, without brackets.

    Hex pieces throughout, an embedded IPv4 address included, with the first
    longest run of two or more zero pieces compressed; a zone ID is invalid.
    """
    try:
        if "%" in host:
            raise ValueError  # noqa: TRY301 - one error for every invalid literal
        value = int(ipaddress.IPv6Address(host))
    except ValueError:
        msg = "Invalid URL"
        raise UrlError(msg) from None
    pieces = [(value >> (16 * (7 - i))) & 0xFFFF for i in range(8)]
    best, best_length, start = -1, 1, None
    for index, piece in enumerate([*pieces, 1]):
        if piece == 0 and start is None:
            start = index
        elif piece != 0 and start is not None:
            if index - start > best_length:
                best, best_length = start, index - start
            start = None
    if best < 0:
        return ":".join(f"{p:x}" for p in pieces)
    head = ":".join(f"{p:x}" for p in pieces[:best])
    tail = ":".join(f"{p:x}" for p in pieces[best + best_length :])
    return f"{head}::{tail}"


def _ascii_host(host: str) -> str:
    """Return the host as the URL standard serializes it: A-labels, numeric hosts dotted."""
    if ":" in host:
        return _whatwg_ipv6(host)
    try:
        host = host if host.isascii() else idna.encode(host, uts46=True).decode("ascii")
    except idna.IDNAError:
        msg = "Invalid URL"
        raise UrlError(msg) from None
    return _whatwg_ipv4(host) or host.lower()


def request_host(url: str) -> str:
    """The URL's host as a request names it to curl: A-labels, a numeric host dotted."""
    return _ascii_host(urlsplit(url).hostname or "")


def check_url(url: str) -> str:
    """Return the URL to request, upgraded to https; raise UrlError otherwise.

    The host is written as the URL standard serializes it, so a Unicode name
    becomes its A-labels and a numeric host its dotted address.
    """
    if len(url) > MAX_URL_LENGTH:
        msg = "Invalid URL"
        raise UrlError(msg)
    try:
        parts = urlsplit(url)
        port = parts.port
    except ValueError:
        msg = "Invalid URL"
        raise UrlError(msg) from None
    host = parts.hostname or ""
    if parts.scheme not in DEFAULT_PORTS or not host:
        msg = "Invalid URL"
        raise UrlError(msg)
    if parts.username is not None or parts.password is not None:
        msg = "Invalid URL"
        raise UrlError(msg)
    host = _ascii_host(host)
    named = f"[{host}]" if ":" in host else host
    dropped = {None, 80} if parts.scheme == "http" else {None}
    netloc = named if port in dropped else f"{named}:{port}"
    return urlunsplit(parts._replace(scheme="https", netloc=netloc))


# What stays unescaped once a path or query is decoded and encoded again.
_KEEP = "/!$&'()*+,;=:@~-._"


def canonical(url: str) -> str:
    """The URL with spelling differences gone, for comparing two that name one resource.

    The scheme and host are lowercased, the host in A-labels, a default port
    and the fragment are dropped, an empty path is "/", and the path and
    query are decoded and encoded again, so Firefox's percent-encoding of a
    Unicode path matches the URL as written.
    """
    try:
        parts = urlsplit(url)
        port = parts.port
        host = _ascii_host(parts.hostname or "")
    except ValueError, UrlError:
        return url
    scheme = parts.scheme.lower()
    named = f"[{host}]" if ":" in host else host
    netloc = named if port in {None, DEFAULT_PORTS.get(scheme)} else f"{named}:{port}"
    path = quote(unquote(parts.path or "/"), safe=_KEEP)
    query = quote(unquote(parts.query), safe=_KEEP + "?")
    return urlunsplit((scheme, netloc, path, query, ""))


def _port(parts: SplitResult) -> int | None:
    port = parts.port
    return None if port == DEFAULT_PORTS.get(parts.scheme) else port


def _strip_www(host: str) -> str:
    return host.removeprefix("www.")


def redirect_allowed(origin: str, target: str) -> bool:
    """Whether WebFetch follows a redirect from origin to target itself.

    Only a redirect to the same host, give or take a leading www., on the same
    scheme and port and without credentials is followed; the rest are reported.
    """
    try:
        source, dest = urlsplit(origin), urlsplit(target)
        if dest.scheme != source.scheme or _port(dest) != _port(source):
            return False
    except ValueError:
        return False
    source_host = source.hostname or ""
    bare = _strip_www(source_host)
    if dest.username is not None or dest.password is not None:
        return False
    return _strip_www(dest.hostname or "") == bare
