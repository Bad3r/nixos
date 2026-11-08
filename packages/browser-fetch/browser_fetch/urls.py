# Copyright (c) 2026 Bad3r
"""URL checks and the redirect policy of Claude Code 2.1.319's WebFetch."""

from __future__ import annotations

import ipaddress
import re
import socket
from dataclasses import dataclass
from typing import TYPE_CHECKING
from urllib.parse import SplitResult, quote, unquote, urlsplit, urlunsplit

import idna

if TYPE_CHECKING:
    from collections.abc import Callable

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


def _ascii_host(host: str) -> str:
    """Return the host as the URL standard serializes it: A-labels, numeric hosts dotted."""
    try:
        host = host if host.isascii() else idna.encode(host, uts46=True).decode("ascii")
    except idna.IDNAError:
        msg = "Invalid URL"
        raise UrlError(msg) from None
    return _whatwg_ipv4(host) or host.lower()


# Destinations no fetch reaches, by the address a name resolves to: this
# machine, private, shared, link-local, documentation, benchmarking, reserved
# and multicast ranges. The browser's namespace refuses routes to them too.
BLOCKED_NETWORKS = tuple(
    ipaddress.ip_network(network)
    for network in (
        "0.0.0.0/8",
        "10.0.0.0/8",
        "100.64.0.0/10",
        "127.0.0.0/8",
        "169.254.0.0/16",
        "172.16.0.0/12",
        "192.0.0.0/24",
        "192.0.2.0/24",
        "192.168.0.0/16",
        "198.18.0.0/15",
        "198.51.100.0/24",
        "203.0.113.0/24",
        "224.0.0.0/4",
        "240.0.0.0/4",
        "::/128",
        "::1/128",
        "::ffff:0:0/96",
        "64:ff9b:1::/48",
        "100::/64",
        "2001:db8::/32",
        "fc00::/7",
        "fe80::/10",
        "fec0::/10",
        "ff00::/8",
    )
)
_NAT64 = ipaddress.IPv6Network("64:ff9b::/96")


class AddressError(Exception):
    """The host has no address a fetch may connect to."""


class PrivateAddressError(AddressError):
    """The host resolves to this machine or a non-public network."""


def blocked_address(address: ipaddress.IPv4Address | ipaddress.IPv6Address) -> bool:
    """Whether a fetch may not connect to the address."""
    if isinstance(address, ipaddress.IPv6Address):
        if address.ipv4_mapped is not None:
            return blocked_address(address.ipv4_mapped)
        if address in _NAT64:
            return blocked_address(ipaddress.IPv4Address(int(address) & 0xFFFFFFFF))
    return not address.is_global or any(address in network for network in BLOCKED_NETWORKS)


def lookup(host: str, port: int) -> list[str]:
    """The addresses the system resolver gives for host, in its order."""
    try:
        infos = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    except OSError, UnicodeError:
        return []
    return list(dict.fromkeys(str(info[4][0]) for info in infos))


def request_host(url: str) -> str:
    """The URL's host as a request names it to curl: A-labels, a numeric host dotted."""
    return _ascii_host(urlsplit(url).hostname or "")


@dataclass(frozen=True)
class Pinned:
    """A request URL and the checked addresses curl must connect to."""

    url: str
    host: str
    port: int
    addresses: tuple[str, ...]


def pin(url: str, resolve: Callable[[str, int], list[str]] = lookup) -> Pinned:
    """Resolve url's host once and refuse it unless every address is public.

    The returned URL spells the host as the pin names it, so curl uses the
    pinned addresses instead of resolving the name again.
    """
    parts = urlsplit(url)
    host = request_host(url)
    port = parts.port or DEFAULT_PORTS.get(parts.scheme, 443)
    try:
        literal = ipaddress.ip_address(host)
    except ValueError:
        found = resolve(host, port)
    else:
        found = [str(literal)]
    if not found:
        msg = f"the host name {host} did not resolve"
        raise AddressError(msg)
    for address in found:
        if blocked_address(ipaddress.ip_address(address.split("%", 1)[0])):
            msg = f"{host} resolves to {address}, an address on this machine or a private network"
            raise PrivateAddressError(msg)
    named = f"[{host}]" if ":" in host else host
    netloc = named if parts.port is None else f"{named}:{parts.port}"
    return Pinned(urlunsplit(parts._replace(netloc=netloc)), host, port, tuple(found))


def check_url(url: str) -> str:
    """Return the URL to request, upgraded to https; raise UrlError otherwise.

    The host is written as the URL standard serializes it, so a Unicode name
    becomes its A-labels and a numeric host its dotted address. An IPv6
    literal is refused as dotless, as WebFetch's hostname check refuses it.
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
    if "." not in host or ":" in host:
        msg = (
            "WebFetch cannot fetch localhost or other hostnames without a dot. "
            "To reach a local server, use Bash with curl instead."
        )
        raise UrlError(msg)
    host = _ascii_host(host)
    dropped = {None, 80} if parts.scheme == "http" else {None}
    netloc = host if port in dropped else f"{host}:{port}"
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
