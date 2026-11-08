# Copyright (c) 2026 Bad3r
"""Camoufox's cookie jar: Gecko's cookies.sqlite, read and written as Firefox does.

Gecko references are to netwerk/cookie/ of Firefox 158.0.1, Camoufox's base,
with the default preferences Camoufox keeps.
"""

from __future__ import annotations

import contextlib
import functools
import ipaddress
import sqlite3
import time
from dataclasses import dataclass, field, replace
from typing import TYPE_CHECKING
from urllib.parse import quote_plus, unquote_plus, urlsplit

from publicsuffixlist import PublicSuffixList

from browser_fetch import dates

if TYPE_CHECKING:
    from collections.abc import Generator, Iterable, Iterator
    from pathlib import Path

DB_NAME = "cookies.sqlite"
# COOKIES_SCHEMA_VERSION (CookiePersistentStorage.cpp). Gecko takes any other
# version for an upgrade or a downgrade, and drops the whole table on a
# downgrade whose columns it does not know.
SCHEMA_VERSION = 17
# CreateTableWorker, verbatim.
CREATE_TABLE = (
    "CREATE TABLE moz_cookies ("
    "id INTEGER PRIMARY KEY, "
    "originAttributes TEXT NOT NULL DEFAULT '', "
    "name TEXT, "
    "value TEXT, "
    "host TEXT, "
    "path TEXT, "
    "expiry INTEGER, "
    "lastAccessed INTEGER, "
    "creationTime INTEGER, "
    "isSecure INTEGER, "
    "isHttpOnly INTEGER, "
    "inBrowserElement INTEGER DEFAULT 0, "
    "sameSite INTEGER DEFAULT 0, "
    "schemeMap INTEGER DEFAULT 0, "
    "isPartitionedAttributeSet INTEGER DEFAULT 0, "
    "updateTime INTEGER, "
    "CONSTRAINT moz_uniqueid UNIQUE (name, host, path, originAttributes)"
    ")"
)
# mozStorage's page size for a database it creates.
PAGE_SIZE = 32768
# Gecko's mStmtInsert; inBrowserElement keeps its default.
_INSERT = (
    "INSERT INTO moz_cookies (originAttributes, name, value, host, path, expiry,"
    " lastAccessed, creationTime, isSecure, isHttpOnly, sameSite, schemeMap,"
    " isPartitionedAttributeSet, updateTime)"
    " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
)
_KEY = "name = ? AND host = ? AND path = ? AND originAttributes = ?"
_COLUMNS = (
    "originAttributes, name, value, host, path, expiry, lastAccessed, creationTime,"
    " isSecure, isHttpOnly, sameSite, schemeMap, isPartitionedAttributeSet, updateTime"
)
# How long a write waits for SQLite's own lock; the profile lock is held already.
BUSY_SECONDS = 10
# nsICookie's sameSite and schemeType values.
SAME_SITE_NONE = 0
SAME_SITE_LAX = 1
SAME_SITE_STRICT = 2
SAME_SITE_UNSET = 256
SCHEME_HTTP = 1
SCHEME_HTTPS = 2
# network.cookie.maxageCap: no cookie lives longer than 400 days.
MAXAGE_CAP_SECONDS = 34_560_000
# network.cookie.staleThreshold: an identical cookie set again within this
# long of its last access leaves the stored row alone (CookieStorage::AddCookie).
STALE_SECONDS = 60
# CookieParser.cpp and CookieValidation.cpp limits, in bytes.
ATTRIBUTE_MAX_LENGTH = 1024
MAX_BYTES_PER_COOKIE = 4096
MAX_BYTES_PER_PATH = 1024
MAX_BYTES_PER_DOMAIN = 1024
# A session cookie's expiry in Gecko (CookieParser::Parse): never.
SESSION_EXPIRY_MS = 2**63 - 1
EXPIRED_MS = -(2**63)
# Characters that would break the Cookie header or curl's config file.
_UNSENDABLE = frozenset("\r\n\0;")
# CookieValidation::CheckName and CheckValue.
_ILLEGAL_VALUE = frozenset(chr(c) for c in (*range(0x09), *range(0x0A, 0x20), 0x3B, 0x7F))
_ILLEGAL_NAME = _ILLEGAL_VALUE | {"="}
_BLANKS = " \t"
# Checked with the name's case ignored (CookiePrefixes.cpp), longest first.
_PREFIXES = ("__host-http-", "__host-", "__http-", "__secure-")
_SAME_SITE = {"lax": SAME_SITE_LAX, "strict": SAME_SITE_STRICT, "none": SAME_SITE_NONE}
_ASCII_LOWER = str.maketrans("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")

type Key = tuple[str, str, str, str]


class CookieError(Exception):
    """Camoufox's cookie database cannot be read or written safely."""


@dataclass(frozen=True)
class Cookie:
    """One cookie as Gecko stores it: host with a leading dot for a domain cookie."""

    name: str
    value: str
    host: str
    path: str
    expiry_ms: int
    secure: bool
    # Microseconds, as Gecko's creationTime.
    created: int
    http_only: bool = False
    same_site: int = SAME_SITE_UNSET
    # The CHIPS partition, "(scheme,site)", or "" for the unpartitioned jar.
    partition: str = ""
    session: bool = False
    # Microseconds, as Gecko's lastAccessed and updateTime.
    accessed: int = 0
    updated: int = 0
    scheme_map: int = SCHEME_HTTPS

    @property
    def key(self) -> Key:
        """What makes two cookies the same cookie in one jar (moz_uniqueid)."""
        return (self.name, self.host, self.path, self.partition)

    @property
    def origin_attributes(self) -> str:
        """The row's originAttributes, as OriginAttributes::CreateSuffix writes it."""
        return origin_attributes(self.partition)

    def expired(self, now: int) -> bool:
        """Whether Gecko counts the cookie as gone at now, in milliseconds."""
        return self.expiry_ms <= now

    def matches(self, url: str, now: int) -> bool:
        """Whether a browser sends this cookie with a top-level request for url."""
        parts = urlsplit(url)
        return (
            not self.expired(now)
            and (not self.secure or parts.scheme == "https")
            and domain_match(parts.hostname or "", self.host)
            and path_match(parts.path or "/", self.path)
            and (not self.partition or self.partition == partition_key(url))
        )

    @property
    def pair(self) -> str:
        """The cookie as it appears in a Cookie header (ComposeCookieString)."""
        return f"{self.name}={self.value}" if self.name else self.value


@functools.cache
def _suffixes() -> PublicSuffixList:
    return PublicSuffixList()


def _is_ip(host: str) -> bool:
    try:
        ipaddress.ip_address(host)
    except ValueError:
        return False
    return True


def base_domain(host: str) -> str | None:
    """The host's registrable domain, or None for an address or a public suffix itself.

    Gecko's eTLD service reads the whole Public Suffix List, private
    domains included, and takes an unlisted top-level label for a suffix.
    """
    if _is_ip(host):
        return None
    return _suffixes().privatesuffix(host)


def site(host: str) -> str:
    """The site a partition key names: the base domain, else the host itself.

    PopulateTopLevelInfoFromURI with privacy.dynamic_firstparty.use_site.
    """
    return base_domain(host) or host


def partition_key(url: str) -> str:
    """The partition a top-level document at url stores its CHIPS cookies in.

    MakeTopLevelInfo writes "(scheme,site)", with no port.
    """
    parts = urlsplit(url)
    return f"({parts.scheme},{site((parts.hostname or '').lower())})"


def origin_attributes(partition: str) -> str:
    """The originAttributes text of a cookie in partition, or "" unpartitioned.

    CreateSuffix sanitizes ":" to "+", then URLParams percent-encodes all but
    ASCII letters, digits and "*-._", and "*" is encoded as well.
    """
    if not partition:
        return ""
    encoded = quote_plus(partition.replace(":", "+"), safe="-._").replace("~", "%7E")
    return f"^partitionKey={encoded}"


def _partition_of(attributes: str) -> str | None:
    """The partition of a row's originAttributes; None for any other jar.

    Containers, private browsing, first-party isolation, and partitions of
    a foreign ancestor ("(scheme,site,f)") are jars a top-level request
    never asks.
    """
    if not attributes:
        return ""
    name, _, encoded = attributes.removeprefix("^").partition("=")
    if name != "partitionKey" or "&" in encoded:
        return None
    partition = unquote_plus(encoded).replace("+", ":")
    if partition.count(",") != 1:
        return None
    return partition


def _valid_host(host: str) -> bool:
    """Whether Gecko keeps a row of host on load (GetBaseDomainFromHost).

    A domain cookie on an address or a public suffix has no base domain.
    """
    if not host or host == ".":
        return False
    return not host.startswith(".") or base_domain(host[1:]) is not None


def domain_match(request_host: str, cookie_host: str) -> bool:
    """RFC 6265 section 5.1.3, with Gecko's leading dot marking a domain cookie."""
    request_host = request_host.lower()
    if not cookie_host.startswith("."):
        return request_host == cookie_host
    domain = cookie_host[1:]
    return request_host == domain or (
        request_host.endswith(f".{domain}") and not _is_ip(request_host)
    )


def path_match(request_path: str, cookie_path: str) -> bool:
    """RFC 6265 section 5.1.4, as CookieCommons::PathMatches."""
    if not cookie_path:
        return False
    if request_path == cookie_path:
        return True
    if not request_path.startswith(cookie_path):
        return False
    return cookie_path.endswith("/") or request_path[len(cookie_path)] == "/"


def now_us() -> int:
    """Return the time in Gecko's creationTime unit."""
    return time.time_ns() // 1000


def for_request(cookies: Iterable[Cookie], url: str, now: int) -> list[Cookie]:
    """Return the cookies a request for url carries, in Gecko's order.

    Longest path first, then earliest creation (CompareCookiesForSending).
    """
    sent = [cookie for cookie in cookies if cookie.matches(url, now)]
    return sorted(sent, key=lambda cookie: (-len(cookie.path), cookie.created))


def header(cookies: list[Cookie]) -> str:
    """Return the Cookie header value for the cookies, in order."""
    return "; ".join(cookie.pair for cookie in cookies)


@contextlib.contextmanager
def _connected(database: Path) -> Generator[sqlite3.Connection]:
    try:
        connection = sqlite3.connect(database, timeout=BUSY_SECONDS, isolation_level=None)
    except sqlite3.Error as error:
        msg = f"the cookie database {database} could not be opened: {error}"
        raise CookieError(msg) from None
    try:
        yield connection
    except sqlite3.Error as error:
        msg = f"the cookie database {database} failed: {error}"
        raise CookieError(msg) from None
    finally:
        connection.close()


def _has_table(connection: sqlite3.Connection) -> bool:
    return bool(
        connection.execute(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'moz_cookies'"
        ).fetchone()
    )


def _check_version(connection: sqlite3.Connection, database: Path) -> bool:
    """Whether the table is there; an empty file or a bare version 17 has none yet.

    Gecko creates the table in both cases (TryInitDB); any other version is
    left for Gecko alone, since writing under it could cost the whole jar.
    """
    version = int(connection.execute("PRAGMA user_version").fetchone()[0])
    present = _has_table(connection)
    if version == SCHEMA_VERSION or (version == 0 and not present):
        return present
    msg = (
        f"the cookie database {database} has schema version {version}, not "
        f"{SCHEMA_VERSION}; browser-fetch neither reads nor writes it"
    )
    raise CookieError(msg)


type _Row = tuple[str, str, str, str, str, int, int, int, int, int, int, int, int, int]


def _row(row: _Row) -> Cookie | None:
    attrs, name, value, host, path, expiry, accessed, created, secure, http_only = row[:10]
    same_site, scheme_map, flagged, updated = row[10:]
    partition = _partition_of(attrs)
    if partition is None or (partition and not flagged):
        return None
    if not name or not _valid_host(host) or _UNSENDABLE.intersection(name + value):
        return None
    if same_site not in {SAME_SITE_NONE, SAME_SITE_LAX, SAME_SITE_STRICT, SAME_SITE_UNSET}:
        same_site = SAME_SITE_UNSET
    return Cookie(
        name,
        value,
        host,
        path,
        expiry,
        bool(secure),
        created,
        http_only=bool(http_only),
        same_site=same_site,
        partition=partition,
        accessed=accessed,
        updated=updated,
        scheme_map=scheme_map,
    )


def read(database: Path) -> list[Cookie]:
    """Return the cookies a top-level request may carry, from Camoufox's database.

    The caller holds the profile lock, so no browser has the database open.
    Gecko asks two jars on a top-level request (CookieService.cpp): the
    unpartitioned one and, for cookies set with Partitioned, the request
    site's own partition, matched in Cookie.matches(). Rows Gecko drops on
    load (Read(): nameless, or a domain with no base domain), partitioned
    rows without the Partitioned flag and rows of other jars are left out.
    """
    if not database.exists():
        return []
    with _connected(database) as connection:
        if not _check_version(connection, database):
            return []
        rows = connection.execute(
            "SELECT coalesce(originAttributes, ''), coalesce(name, ''), coalesce(value, ''),"
            " coalesce(host, ''), coalesce(path, ''), coalesce(expiry, 0),"
            " coalesce(lastAccessed, 0), coalesce(creationTime, 0), coalesce(isSecure, 0),"
            " coalesce(isHttpOnly, 0), coalesce(sameSite, 0), coalesce(schemeMap, 0),"
            " coalesce(isPartitionedAttributeSet, 0), coalesce(updateTime, 0)"
            " FROM moz_cookies"
        ).fetchall()
    return [cookie for cookie in map(_row, rows) if cookie is not None]


class CreationClock:
    """GenerateUniqueCreationTimeInUSec: never the same creation time twice."""

    def __init__(self) -> None:
        """Start below any time."""
        self.last = 0

    def next(self, now: int) -> int:
        """Now in microseconds, or just after the last time handed out when that is later."""
        self.last = max(now, self.last + 1)
        return self.last


# One per process, as Gecko's gLastCreationTimeInUSec is.
CREATION = CreationClock()


def _ascii_lower(text: str) -> str:
    return text.translate(_ASCII_LOWER)


def _strip(text: str) -> str:
    return text.strip(_BLANKS)


def _tokens(line: str) -> Iterator[tuple[str, str, bool]]:
    """Each token and value of a Set-Cookie value (CookieParser::GetTokenValue)."""
    at, end = 0, len(line)
    while True:
        stop = at
        while stop < end and line[stop] not in ";=":
            stop += 1
        token = _strip(line[at:stop])
        equals = stop < end and line[stop] == "="
        value = ""
        if equals:
            start = stop + 1
            stop = line.find(";", start)
            stop = end if stop < 0 else stop
            value = _strip(line[start:stop])
        yield token, value, equals
        if stop >= end:
            return
        at = stop + 1


def _control(text: str) -> bool:
    return any((ord(c) <= 0x1F and c != "\t") or c == "\x7f" for c in text)  # noqa: PLR2004


def _octets(text: str) -> int:
    return len(text.encode("utf-8", "surrogatepass"))


def _time_ms(text: str) -> int | None:
    """A date in milliseconds as GetExpiry reads it, or None when PR_ParseTimeString fails."""
    microseconds = dates.parse_time(text)
    if microseconds is None:
        return None
    # int64_t division, which truncates toward zero.
    return -(-microseconds // 1000) if microseconds < 0 else microseconds // 1000


def _default_path(path: str) -> str:
    """The directory of the request path without its last slash (GetPathFromURI)."""
    directory = path[: path.rfind("/") + 1] if "/" in path else "/"
    if directory.count("/") > 1:
        directory = directory.removesuffix("/")
    return directory or "/"


@dataclass
class _Attributes:
    path: str = ""
    domain: str = ""
    expires: str = ""
    max_age: str = ""
    secure: bool = False
    http_only: bool = False
    partitioned: bool = False
    same_site: int = SAME_SITE_UNSET

    def take(self, token: str, value: str) -> None:
        """Keep one attribute; an oversized value is ignored, a later one wins."""
        key = _ascii_lower(token)
        sized = _octets(value) <= ATTRIBUTE_MAX_LENGTH
        if key in {"path", "domain", "expires", "max-age"}:
            if sized:
                setattr(self, key.replace("-", "_"), value)
        elif key == "secure":
            self.secure = True
        elif key == "partitioned":
            self.partitioned = True
        elif key == "httponly":
            self.http_only = True
        elif key == "samesite":
            self.same_site = _SAME_SITE.get(_ascii_lower(value), SAME_SITE_UNSET)


def _expiry(attributes: _Attributes, created_ms: int, date: str | None) -> int | None:
    """The expiry in milliseconds, or None for a session cookie (CookieParser::GetExpiry)."""
    cap = created_ms + MAXAGE_CAP_SECONDS * 1000
    max_age = attributes.max_age
    if max_age.startswith("-"):
        return EXPIRED_MS
    if max_age and max_age.isascii() and max_age.isdigit():
        return created_ms + min(int(max_age), MAXAGE_CAP_SECONDS) * 1000
    if not attributes.expires:
        return None
    expires = _time_ms(attributes.expires)
    if expires is None:
        return None
    # The server's clock, from its Date header, against this one.
    server = _time_ms(date) if date else None
    if server is not None:
        expires += created_ms - server
    return min(expires, cap)


def _host(attributes: _Attributes, host: str) -> str | None:
    """The cookie's host: the request's, or ".domain" (FixDomain, CheckDomain)."""
    if not attributes.domain:
        return host
    domain = attributes.domain
    if len(domain) > 1 and domain.startswith("."):
        domain = domain[1:]
    domain = _ascii_lower(domain)
    base = base_domain(host)
    if base is None:
        return host if domain == host else None
    if _subdomain(domain, base) and _subdomain(host, domain):
        return f".{domain}"
    return None


def _subdomain(a: str, b: str) -> bool:
    """CookieCommons::IsSubdomainOf."""
    return a == b or (len(a) > len(b) and a.endswith(f".{b}"))


def _prefix_allows(name: str, path: str, host: str, *, secure: bool, http_only: bool) -> bool:
    """CookiePrefixes::Check over the Path attribute as sent, from a secure origin."""
    lowered = _ascii_lower(name)
    prefix = next((p for p in _PREFIXES if lowered.startswith(p)), None)
    if prefix is None:
        return True
    host_bound = not host.startswith(".") and path == "/"
    return {
        "__host-http-": secure and http_only and host_bound,
        "__host-": secure and host_bound,
        "__http-": secure and http_only,
        "__secure-": secure,
    }[prefix]


def _valid(
    name: str, value: str, attributes: _Attributes, host: str, *, secure_origin: bool
) -> bool:
    """CookieValidation::ValidateInContext for a top-level response."""
    secure = attributes.secure
    return (
        bool(name)
        and _octets(name) + _octets(value) <= MAX_BYTES_PER_COOKIE
        and name[0] != " "
        and name[-1] != " "
        and not _ILLEGAL_NAME.intersection(name)
        and (not value or (value[0] != " " and value[-1] != " "))
        and not _ILLEGAL_VALUE.intersection(value)
        and _octets(attributes.path) <= MAX_BYTES_PER_PATH
        and "\t" not in attributes.path
        and _octets(host) <= MAX_BYTES_PER_DOMAIN
        and (secure or attributes.same_site != SAME_SITE_NONE)
        and _prefix_allows(
            name, attributes.path, host, secure=secure, http_only=attributes.http_only
        )
        and (secure_origin or not secure)
        and (secure or not attributes.partitioned)
    )


def parse_set_cookie(line: str, url: str, now: int, date: str | None = None) -> Cookie | None:
    """Parse one Set-Cookie value of a top-level response for url, as Gecko does.

    now is the response time in microseconds and date the response's Date
    header. None when Gecko would reject the cookie. A cookie whose expiry
    has passed is returned: storing it deletes the cookie of its key.
    """
    tokens = _tokens(line)
    first, first_value, equals = next(tokens)
    # network.cookie.valueless_cookie: a lone token is the name, with no value.
    name, value = (first, first_value) if equals else (first, "")
    attributes = _Attributes()
    for token, raw, _ in tokens:
        if _control(token) or _control(raw):
            return None
        attributes.take(token, raw)
    parts = urlsplit(url)
    request_host = (parts.hostname or "").lower()
    host = _host(attributes, request_host)
    secure_origin = parts.scheme == "https"
    if host is None or not _valid(name, value, attributes, host, secure_origin=secure_origin):
        return None
    created = CREATION.next(now)
    expiry = _expiry(attributes, created // 1000, date)
    path = attributes.path
    if not path.startswith("/"):
        path = _default_path(parts.path or "/")
    return Cookie(
        name,
        value,
        host,
        path,
        SESSION_EXPIRY_MS if expiry is None else expiry,
        attributes.secure,
        created,
        http_only=attributes.http_only,
        same_site=attributes.same_site,
        partition=partition_key(url) if attributes.partitioned else "",
        session=expiry is None,
        accessed=now,
        updated=created,
        scheme_map=SCHEME_HTTPS if secure_origin else SCHEME_HTTP,
    )


def _same(old: Cookie, new: Cookie) -> bool:
    """Whether AddCookie keeps the old cookie as it is."""
    return (
        old.value == new.value
        and old.expiry_ms == new.expiry_ms
        and old.secure == new.secure
        and old.session == new.session
        and old.http_only == new.http_only
        and old.same_site == new.same_site
        and old.scheme_map == new.scheme_map
    )


def _stale(cookie: Cookie, now: int) -> bool:
    return now - cookie.accessed > STALE_SECONDS * 1_000_000


def _added(old: Cookie | None, new: Cookie, now: int) -> Cookie | None:
    """The cookie of new's key once Gecko's AddCookie has run, or None when nothing changes.

    An expired result deletes the key. now is in microseconds.
    """
    now_ms = now // 1000
    if old is None or old.expired(now_ms):
        return None if new.expired(now_ms) else new
    if _same(old, new) and not _stale(old, now):
        return None
    if new.expired(now_ms):
        return new
    return replace(new, created=old.created, scheme_map=old.scheme_map | new.scheme_map)


@dataclass
class Jar:
    """One fetch's view of the jar: the rows read from it, and what the fetch's responses did.

    changed holds the latest cookie of each key a response set, an expired
    one for a deletion; unsaved holds the keys not yet written back.
    """

    stored: dict[Key, Cookie] = field(default_factory=dict[Key, Cookie])
    changed: dict[Key, Cookie] = field(default_factory=dict[Key, Cookie])
    unsaved: set[Key] = field(default_factory=set[Key])

    @classmethod
    def of(cls, cookies: Iterable[Cookie]) -> Jar:
        """A jar holding the rows read from the database."""
        return cls(stored={cookie.key: cookie for cookie in cookies})

    def get(self, key: Key) -> Cookie | None:
        """The cookie of key as the fetch sees it now."""
        return self.changed.get(key, self.stored.get(key))

    def cookies(self) -> list[Cookie]:
        """Every cookie as the fetch sees it: a response's change over the stored row."""
        return list({**self.stored, **self.changed}.values())

    def receive(self, url: str, set_cookies: Iterable[str], now: int, date: str | None) -> None:
        """Apply a response's Set-Cookie values for url, in order, as Gecko's AddCookie does."""
        for line in set_cookies:
            cookie = parse_set_cookie(line, url, now, date)
            if cookie is None:
                continue
            result = _added(self.get(cookie.key), cookie, now)
            if result is not None:
                self.changed[cookie.key] = result
                self.unsaved.add(cookie.key)

    def pending(self) -> list[Cookie]:
        """The changes not yet written to the database."""
        return [self.changed[key] for key in self.unsaved]

    def received(self, now: int) -> list[Cookie]:
        """The live cookies the fetch's responses set, now in milliseconds."""
        return [cookie for cookie in self.changed.values() if not cookie.expired(now)]


def _stored_row(connection: sqlite3.Connection, cookie: Cookie) -> Cookie | None:
    row = connection.execute(
        f"SELECT {_COLUMNS} FROM moz_cookies WHERE {_KEY}",  # noqa: S608 - fixed text
        (cookie.name, cookie.host, cookie.path, cookie.origin_attributes),
    ).fetchone()
    if row is None:
        return None
    return Cookie(
        row[1],
        row[2] or "",
        row[3],
        row[4],
        row[5],
        bool(row[8]),
        row[7],
        accessed=row[6] or 0,
        http_only=bool(row[9]),
        same_site=row[10],
        scheme_map=row[11] or 0,
        partition=cookie.partition,
        updated=row[13] or 0,
    )


def store(database: Path, cookies: Iterable[Cookie], now: int) -> int:
    """Write the cookies into Camoufox's database as Gecko would have; return the rows changed.

    The caller holds the profile lock, so no browser has the database open,
    and no connection is left open on return. Each cookie meets the row of its
    key as it is now: a persistent cookie replaces it (DELETE, then INSERT,
    as Gecko's write queue does), keeping its creation time and merging its
    scheme map; a session cookie or an expired one removes it, since Gecko
    never stores a session cookie. A database that does not exist yet is
    created as Gecko creates one.
    """
    changes = list(cookies)
    if not changes:
        return 0
    database.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    written = 0
    with _connected(database) as connection:
        if not _check_version(connection, database):
            # Before any table, and outside a transaction, as mozStorage does.
            connection.execute(f"PRAGMA page_size = {PAGE_SIZE}")
            connection.execute("PRAGMA journal_mode = WAL")
        connection.execute("BEGIN IMMEDIATE")
        try:
            if not _check_version(connection, database):
                connection.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")
                connection.execute(CREATE_TABLE)
            for cookie in changes:
                written += _store_one(connection, cookie, now)
        except BaseException:
            connection.execute("ROLLBACK")
            raise
        connection.execute("COMMIT")
    return written


def _store_one(connection: sqlite3.Connection, cookie: Cookie, now: int) -> int:
    key = (cookie.name, cookie.host, cookie.path, cookie.origin_attributes)
    old = _stored_row(connection, cookie)
    if cookie.session or cookie.expired(now // 1000):
        return connection.execute(f"DELETE FROM moz_cookies WHERE {_KEY}", key).rowcount  # noqa: S608
    if old is not None and not old.expired(now // 1000):
        if _same(old, cookie) and not _stale(old, now):
            return 0
        cookie = replace(cookie, created=old.created, scheme_map=old.scheme_map | cookie.scheme_map)
    connection.execute(f"DELETE FROM moz_cookies WHERE {_KEY}", key)  # noqa: S608
    connection.execute(
        _INSERT,
        (
            cookie.origin_attributes,
            cookie.name,
            cookie.value,
            cookie.host,
            cookie.path,
            cookie.expiry_ms,
            cookie.accessed,
            cookie.created,
            int(cookie.secure),
            int(cookie.http_only),
            cookie.same_site,
            cookie.scheme_map,
            int(bool(cookie.partition)),
            cookie.updated,
        ),
    )
    return 1
