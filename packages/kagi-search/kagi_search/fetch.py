# Copyright (c) 2026 Bad3r
"""Public http(s) pages fetched without ever reaching a local or private host."""

from __future__ import annotations

import codecs
import http.client
import ipaddress
import math
import re
import socket
import ssl
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import TYPE_CHECKING, cast, override

from kagi_search import client

if TYPE_CHECKING:
    from collections.abc import Buffer
    from typing import IO

FETCH_TIMEOUT = 20
FETCH_DEADLINE_SECONDS = 40
DEADLINE_SLACK_SECONDS = 0.05
MAX_PAGE_BYTES = 5 * 1024 * 1024
READ_CHUNK = 64 * 1024
CHARSET_SNIFF_BYTES = 4096
PDF_TYPE = "application/pdf"
PDF_PAGE = re.compile(rb"/Type\s*/Page(?![a-zA-Z])")
HTML_TYPES = frozenset({"text/html", "application/xhtml+xml"})
TEXT_TYPES = frozenset({"application/json", "application/xml", "application/javascript"})
LAST_CONTROL_CODE_POINT = 0x20
DELETE_CODE_POINT = 0x7F
NAT64 = ipaddress.IPv6Network("64:ff9b::/96")
NAT64_LOCAL = ipaddress.IPv6Network("64:ff9b:1::/48")
IPV4_COMPATIBLE = ipaddress.IPv6Network("::/96")
IPV4_BITS = 0xFFFFFFFF


class FetchError(Exception):
    """A page could not be fetched."""


class BlockedURLError(FetchError):
    """A URL points somewhere other than a public http(s) host."""


@dataclass(frozen=True)
class Page:
    """A fetched page: final URL, media type, decoded body (None when not text)."""

    url: str
    content_type: str
    body: str | None
    redirected: bool
    pdf_pages: int | None = None


def is_public_address(address: ipaddress.IPv4Address | ipaddress.IPv6Address) -> bool:
    """Tell whether the address is a public unicast internet address."""
    if address.is_multicast or not address.is_global:
        return False
    if isinstance(address, ipaddress.IPv6Address):
        if address in IPV4_COMPATIBLE or address in NAT64_LOCAL:
            return False
        embedded = address.ipv4_mapped or address.sixtofour
        if address in NAT64:
            embedded = ipaddress.IPv4Address(int(address) & IPV4_BITS)
        if embedded is not None:
            return is_public_address(embedded)
    return True


def resolve(host: str, port: int) -> list[str]:
    """Return the host's addresses."""
    try:
        infos = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    except (socket.gaierror, UnicodeError) as error:
        msg = f"cannot resolve {host}: {error}"
        raise FetchError(msg) from None
    return list(dict.fromkeys(str(info[4][0]) for info in infos))


def public_addresses(host: str, port: int) -> list[str]:
    """Return the host's addresses, refusing a host with any non-public one."""
    addresses = resolve(host, port)
    if not addresses:
        msg = f"cannot resolve {host}"
        raise FetchError(msg)
    for address in addresses:
        parsed = ipaddress.ip_address(address.split("%", 1)[0])
        if not is_public_address(parsed):
            msg = (
                f"{host} resolves to the non-public address {parsed}; "
                "only public internet hosts can be opened"
            )
            raise BlockedURLError(msg)
    return addresses


def _deadline_message() -> str:
    return f"the page took longer than {FETCH_DEADLINE_SECONDS} s to download"


def _arm(sock: socket.socket, deadline: float) -> None:
    """Bound the next socket operation by the fetch's remaining wall-clock time."""
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise TimeoutError(_deadline_message())
    sock.settimeout(min(remaining, FETCH_TIMEOUT))


class _DeadlineSocket(socket.socket):
    """TCP socket whose every receive ends by the fetch deadline."""

    deadline: float = math.inf

    @override
    def recv_into(self, buffer: Buffer, nbytes: int = 0, flags: int = 0) -> int:
        _arm(self, self.deadline)
        return super().recv_into(buffer, nbytes, flags)

    @override
    def recv(self, bufsize: int, flags: int = 0) -> bytes:
        _arm(self, self.deadline)
        return super().recv(bufsize, flags)


class _DeadlineSSLSocket(ssl.SSLSocket):
    """TLS socket whose every receive ends by the fetch deadline."""

    deadline: float = math.inf

    @override
    def recv_into(self, buffer: Buffer, nbytes: int | None = None, flags: int = 0) -> int:
        _arm(self, self.deadline)
        return super().recv_into(buffer, nbytes, flags)

    @override
    def recv(self, buflen: int = 1024, flags: int = 0) -> bytes:
        _arm(self, self.deadline)
        return super().recv(buflen, flags)


def _connect(host: str, port: int, deadline: float) -> _DeadlineSocket:
    failure: OSError | None = None
    for address in public_addresses(host, port):
        family = socket.AF_INET6 if ":" in address else socket.AF_INET
        sock = _DeadlineSocket(family, socket.SOCK_STREAM)
        sock.deadline = deadline
        try:
            _arm(sock, deadline)
            sock.connect((address, port))
        except OSError as error:
            sock.close()
            failure = error
        else:
            return sock
    msg = f"cannot connect to {host}: {failure}"
    raise FetchError(msg)


_TLS = ssl.create_default_context()
_TLS.sslsocket_class = _DeadlineSSLSocket


class _PublicHTTPConnection(http.client.HTTPConnection):
    """HTTP connection that connects only to a vetted public address."""

    def __init__(  # noqa: PLR0913 - HTTPConnection's own parameters plus the deadline
        self,
        host: str,
        port: int | None = None,
        timeout: float = FETCH_TIMEOUT,
        source_address: tuple[str, int] | None = None,
        blocksize: int = 8192,
        *,
        deadline: float = math.inf,
    ) -> None:
        """Remember the fetch deadline the connection's reads must meet."""
        super().__init__(host, port, timeout, source_address, blocksize)
        self.deadline = deadline

    @override
    def connect(self) -> None:
        self.sock = _connect(self.host, self.port, self.deadline)


class _PublicHTTPSConnection(http.client.HTTPSConnection):
    """HTTPS connection that connects only to a vetted public address."""

    def __init__(  # noqa: PLR0913 - HTTPSConnection's own parameters plus the deadline
        self,
        host: str,
        port: int | None = None,
        *,
        timeout: float = FETCH_TIMEOUT,
        source_address: tuple[str, int] | None = None,
        blocksize: int = 8192,
        deadline: float = math.inf,
    ) -> None:
        """Remember the fetch deadline the connection's reads must meet."""
        super().__init__(
            host, port, timeout=timeout, source_address=source_address, blocksize=blocksize
        )
        self.deadline = deadline

    @override
    def connect(self) -> None:
        raw = _connect(self.host, self.port, self.deadline)
        try:
            sock = _TLS.wrap_socket(raw, server_hostname=self.host)
        except BaseException:
            raw.close()
            raise
        cast("_DeadlineSSLSocket", sock).deadline = self.deadline
        self.sock = sock


class _PublicHTTPHandler(urllib.request.HTTPHandler):
    def __init__(self, deadline: float) -> None:
        super().__init__()
        self.deadline = deadline

    @override
    def http_open(self, req: urllib.request.Request) -> http.client.HTTPResponse:
        return self.do_open(_PublicHTTPConnection, req, deadline=self.deadline)


class _PublicHTTPSHandler(urllib.request.HTTPSHandler):
    def __init__(self, deadline: float) -> None:
        super().__init__()
        self.deadline = deadline

    @override
    def https_open(self, req: urllib.request.Request) -> http.client.HTTPResponse:
        return self.do_open(_PublicHTTPSConnection, req, deadline=self.deadline)


class _PublicRedirectHandler(urllib.request.HTTPRedirectHandler):
    @override
    def redirect_request(
        self,
        req: urllib.request.Request,
        fp: IO[bytes],
        code: int,
        msg: str,
        headers: http.client.HTTPMessage,
        newurl: str,
    ) -> urllib.request.Request | None:
        try:
            target = normalize_url(newurl)
        except BlockedURLError:
            fp.close()
            raise
        return super().redirect_request(req, fp, code, msg, headers, target)


def public_opener(deadline: float) -> urllib.request.OpenerDirector:
    """Return an opener for public http(s) hosts only: no proxies, files, or cookies.

    Every socket operation of its connections ends by the monotonic deadline.
    """
    director = urllib.request.OpenerDirector()
    for handler in (
        _PublicHTTPHandler(deadline),
        _PublicHTTPSHandler(deadline),
        _PublicRedirectHandler(),
        urllib.request.HTTPDefaultErrorHandler(),
        urllib.request.HTTPErrorProcessor(),
    ):
        director.add_handler(handler)
    return director


def normalize_url(url: str) -> str:
    """Return the URL ready to request; refuse anything but a plain http(s) URL."""
    if "\\" in url or any(
        ord(char) <= LAST_CONTROL_CODE_POINT or ord(char) == DELETE_CODE_POINT for char in url
    ):
        msg = "URLs with whitespace, control characters, or backslashes are refused"
        raise BlockedURLError(msg)
    try:
        parts = urllib.parse.urlsplit(url)
    except ValueError as error:
        msg = f"malformed URL: {error}"
        raise BlockedURLError(msg) from None
    scheme = parts.scheme.lower()
    if scheme not in {"http", "https"}:
        msg = f"only http and https URLs can be opened, not {scheme or 'a relative URL'}"
        raise BlockedURLError(msg)
    if "@" in parts.netloc:
        msg = "URLs with user information are refused"
        raise BlockedURLError(msg)
    try:
        host = parts.hostname
        port = parts.port
    except ValueError as error:
        msg = f"malformed URL: {error}"
        raise BlockedURLError(msg) from None
    if not host:
        msg = "the URL names no host"
        raise BlockedURLError(msg)
    try:
        ascii_host = host.encode("idna").decode("ascii")
    except UnicodeError:
        msg = f"cannot encode the host name {host}"
        raise BlockedURLError(msg) from None
    netloc = f"[{ascii_host}]" if ":" in ascii_host else ascii_host
    if port is not None:
        netloc = f"{netloc}:{port}"
    safe = "/%:@!$&'()*+,;=~-._?"
    return urllib.parse.urlunsplit(
        (
            scheme,
            netloc,
            urllib.parse.quote(parts.path, safe=safe),
            urllib.parse.quote(parts.query, safe=safe),
            urllib.parse.quote(parts.fragment, safe=safe),
        )
    )


def _read(response: http.client.HTTPResponse, deadline: float) -> bytes:
    chunks: list[bytes] = []
    size = 0
    while size < MAX_PAGE_BYTES:
        if time.monotonic() >= deadline:
            raise FetchError(_deadline_message())
        chunk = response.read1(READ_CHUNK)
        if not chunk:
            break
        chunks.append(chunk)
        size += len(chunk)
    return b"".join(chunks)[:MAX_PAGE_BYTES]


def _text_codec(name: str) -> str | None:
    """Return the codec's canonical name if it decodes bytes to text."""
    try:
        b"x".decode(name, errors="replace")
        return codecs.lookup(name).name
    except LookupError, UnicodeError, ValueError:
        return None


def _charset(declared: str | None, body: bytes) -> str:
    candidates = [declared]
    sniffed = re.search(
        rb"""<meta[^>]+charset=["']?([A-Za-z0-9_.:-]+)""", body[:CHARSET_SNIFF_BYTES]
    )
    if sniffed:
        candidates.append(sniffed.group(1).decode("ascii"))
    for candidate in candidates:
        codec = _text_codec(candidate) if candidate else None
        if codec is not None:
            return codec
    return "utf-8"


def is_text(content_type: str) -> bool:
    """Tell whether the media type is shown as text."""
    return (
        content_type in HTML_TYPES
        or content_type.startswith("text/")
        or content_type in TEXT_TYPES
        or content_type.endswith(("+json", "+xml"))
    )


def _failure(reason: object, deadline: float) -> FetchError:
    """Return the error for a failed request, naming the deadline once it has passed."""
    if time.monotonic() >= deadline - DEADLINE_SLACK_SECONDS:
        return FetchError(_deadline_message())
    return FetchError(f"request failed: {reason}")


def pdf_page_count(data: bytes) -> int | None:
    """Return the page count of a PDF whose page objects are uncompressed, else None."""
    count = len(PDF_PAGE.findall(data))
    return count or None


def fetch_page(url: str, deadline: float | None = None) -> Page:
    """Fetch a public http(s) page, following redirects that stay public.

    The fetch ends by FETCH_DEADLINE_SECONDS or the caller's monotonic deadline,
    whichever comes first.
    """
    target = normalize_url(url)
    own = time.monotonic() + FETCH_DEADLINE_SECONDS
    deadline = own if deadline is None else min(own, deadline)
    request = urllib.request.Request(  # noqa: S310 - normalize_url admits only http(s)
        target,
        headers={
            "User-Agent": client.USER_AGENT,
            "Accept": "text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.5",
            "Accept-Language": "en-US,en;q=0.9",
        },
    )
    try:
        with cast(
            "http.client.HTTPResponse",
            public_opener(deadline).open(request, timeout=FETCH_TIMEOUT),
        ) as response:
            final = response.url or target
            content_type = response.headers.get_content_type()
            declared = response.headers.get_content_charset()
            body = _read(response, deadline) if is_text(content_type) else None
            pages = pdf_page_count(_read(response, deadline)) if content_type == PDF_TYPE else None
    except urllib.error.HTTPError as error:
        error.close()
        msg = f"HTTP {error.code} {error.reason}".rstrip()
        raise FetchError(msg) from None
    except urllib.error.URLError as error:
        raise _failure(error.reason, deadline) from None
    except (OSError, http.client.HTTPException) as error:
        raise _failure(str(error) or type(error).__name__, deadline) from None
    try:
        text = None if body is None else body.decode(_charset(declared, body), errors="replace")
    except (LookupError, UnicodeError, ValueError) as error:
        msg = f"cannot decode the page: {error}"
        raise FetchError(msg) from None
    return Page(final, content_type, text, redirected=final != target, pdf_pages=pages)
