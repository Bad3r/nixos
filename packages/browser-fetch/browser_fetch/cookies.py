# Copyright (c) 2026 Bad3r
"""LibreWolf's cookies, read from a consistent copy and matched per RFC 6265."""

from __future__ import annotations

import configparser
import email.utils
import ipaddress
import os
import re
import shutil
import sqlite3
import time
from dataclasses import dataclass, replace
from pathlib import Path
from typing import TYPE_CHECKING, override
from urllib.parse import unquote, urlsplit

if TYPE_CHECKING:
    from collections.abc import Iterable

ATTEMPTS = 5
RETRY_STEP_SECONDS = 0.05
DB_NAME = "cookies.sqlite"
# nsICookie's sameSite values.
SAME_SITE_NONE = 0
SAME_SITE_LAX = 1
SAME_SITE_STRICT = 2
SAME_SITE_UNSET = 256
# Far beyond any expiry, for a session cookie that lives as long as the fetch.
SESSION_EXPIRY_MS = 2**62
# Characters that would break the Cookie header or curl's config file.
_UNSENDABLE = frozenset("\r\n\0;")
_PARTITION_ONLY = re.compile(r"\^partitionKey=([^&]+)")
_MAX_AGE = re.compile(r"-?\d+")


class CookieError(Exception):
    """LibreWolf's cookie database could not be read."""


@dataclass(frozen=True)
class Cookie:
    """One cookie as Gecko stores it: host with a leading dot for a domain cookie."""

    name: str
    value: str
    host: str
    path: str
    expiry_ms: int
    secure: bool
    created: int
    http_only: bool = False
    same_site: int = SAME_SITE_UNSET
    # The CHIPS partition, "(scheme,site[,port])", or "" for the unpartitioned jar.
    partition: str = ""
    session: bool = False

    @property
    def is_domain(self) -> bool:
        """Whether the cookie was set with a Domain attribute."""
        return self.host.startswith(".")

    @property
    def key(self) -> tuple[str, str, str, str]:
        """What makes two cookies the same cookie in one jar."""
        return (self.name, self.host, self.path, self.partition)

    def matches(self, url: str, now_ms: int) -> bool:
        """Whether a browser sends this cookie with a top-level request for url."""
        parts = urlsplit(url)
        return (
            self.expiry_ms > now_ms
            and (not self.secure or parts.scheme == "https")
            and domain_match(parts.hostname or "", self.host)
            and path_match(parts.path or "/", self.path)
            and (not self.partition or partition_matches(self.partition, url))
        )

    @property
    def pair(self) -> str:
        """The cookie as it appears in a Cookie header."""
        return f"{self.name}={self.value}" if self.name else self.value


class _CaseSensitiveParser(configparser.ConfigParser):
    """INI parser that keeps option names as written."""

    @override
    def optionxform(self, optionstr: str) -> str:
        """Return the option name unchanged."""
        return optionstr


def librewolf_root() -> Path:
    """Return LibreWolf's profile root directory."""
    return Path.home() / ".librewolf"


def default_profile(root: Path) -> Path:
    """Return the profile LibreWolf starts with, as its profiles.ini names it."""
    ini = root / "profiles.ini"
    parser = _CaseSensitiveParser(interpolation=None)
    if not parser.read(ini):
        msg = f"no LibreWolf profiles.ini at {ini}"
        raise CookieError(msg)
    profiles = [parser[name] for name in parser.sections() if name.startswith("Profile")]
    installs = [parser[name] for name in parser.sections() if name.startswith("Install")]
    path: str | None = next((s["Default"] for s in installs if s.get("Default")), None)
    if path is not None:
        return root / path
    chosen = next((s for s in profiles if s.get("Default") == "1"), None)
    if chosen is None and len(profiles) == 1:
        chosen = profiles[0]
    if chosen is None or not chosen.get("Path"):
        msg = f"{ini} names no default profile"
        raise CookieError(msg)
    location = Path(chosen["Path"])
    return root / location if chosen.get("IsRelative", "1") == "1" else location


def _state(path: Path) -> tuple[int, int, int] | None:
    try:
        stat = path.stat()
    except FileNotFoundError:
        return None
    return (stat.st_ino, stat.st_size, stat.st_mtime_ns)


def snapshot(profile: Path, into: Path) -> Path:
    """Copy the profile's cookie database and its WAL into a consistent pair.

    LibreWolf holds cookies.sqlite in exclusive locking mode, so SQLite cannot
    read it in place. The WAL goes first: a checkpoint between the two copies
    then leaves an older but consistent pair. Changes during the copy retry it.
    """
    db = profile / DB_NAME
    if not os.access(db, os.R_OK):
        msg = f"no readable cookie database at {db}"
        raise CookieError(msg)
    wal = db.with_name(f"{db.name}-wal")
    copy = into / DB_NAME
    copy_wal = copy.with_name(f"{copy.name}-wal")
    for attempt in range(ATTEMPTS):
        before = (_state(db), _state(wal))
        copy_wal.unlink(missing_ok=True)
        try:
            if before[1] is not None:
                shutil.copyfile(wal, copy_wal)
            shutil.copyfile(db, copy)
        except FileNotFoundError:
            if not db.exists():
                msg = f"no readable cookie database at {db}"
                raise CookieError(msg) from None
            continue
        if (_state(db), _state(wal)) == before:
            return copy
        time.sleep(RETRY_STEP_SECONDS * (attempt + 1))
    msg = f"{db} kept changing while it was copied; try again"
    raise CookieError(msg)


def read(copy: Path) -> list[Cookie]:
    """Return the cookies a top-level request may carry, from a snapshot.

    Gecko asks two jars on a top-level request (CookieService.cpp): the
    unpartitioned one, whatever a row's Partitioned flag, and the request
    site's own partition, from which only cookies set with Partitioned
    count. Rows of containers, private browsing, first-party isolation or
    a partition seen from another site carry other origin attributes and
    are left out; partition rows are matched to the request in matches().
    """
    connection = sqlite3.connect(copy)
    try:
        columns = {row[1] for row in connection.execute("pragma table_info(moz_cookies)")}
        optional = {
            "isHttpOnly": "0",
            "sameSite": str(SAME_SITE_UNSET),
            "isPartitionedAttributeSet": "0",
        }
        picked = ", ".join(c if c in columns else f"{d} as {c}" for c, d in optional.items())
        rows: list[tuple[str, str, str, str, str, int, int, int, int, int, int]] = (
            connection.execute(
                f"""
                select originAttributes, coalesce(name, ''), coalesce(value, ''), lower(host),
                       path, expiry, isSecure, creationTime, {picked}
                from moz_cookies
                """  # noqa: S608 - the interpolated text is built from fixed names
            ).fetchall()
        )
    except sqlite3.Error as error:
        msg = f"the cookie database could not be read: {error}"
        raise CookieError(msg) from None
    finally:
        connection.close()
    cookies: list[Cookie] = []
    for attrs, name, value, host, path, expiry, secure, created, http_only, same, flag in rows:
        if attrs:
            only = _PARTITION_ONLY.fullmatch(attrs)
            if only is None or not flag:
                continue
            partition = unquote(only.group(1))
        else:
            partition = ""
        if _UNSENDABLE.intersection(name + value):
            continue
        cookies.append(
            Cookie(
                name,
                value,
                host,
                path or "/",
                expiry,
                bool(secure),
                created,
                http_only=bool(http_only),
                same_site=same,
                partition=partition,
            )
        )
    return cookies


def partition_matches(partition: str, url: str) -> bool:
    """Whether a CHIPS partition is the top-level site of url.

    Gecko writes a partition as (scheme,site) or (scheme,site,port); the site
    is the registrable domain, which url's host equals or ends in.
    """
    inner = partition.removeprefix("(").removesuffix(")")
    fields = inner.split(",")
    parts = urlsplit(url)
    if len(fields) not in {2, 3} or fields[0] != parts.scheme:
        return False
    port = parts.port if parts.port not in {None, 80 if parts.scheme == "http" else 443} else None
    if (int(fields[2]) if len(fields) == 3 and fields[2].isdigit() else None) != port:  # noqa: PLR2004
        return False
    host = (parts.hostname or "").lower()
    site = fields[1].lower()
    return host == site or (host.endswith(f".{site}") and not _is_ip(host))


def _is_ip(host: str) -> bool:
    try:
        ipaddress.ip_address(host)
    except ValueError:
        return False
    return True


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
    """RFC 6265 section 5.1.4."""
    if request_path == cookie_path:
        return True
    if not request_path.startswith(cookie_path):
        return False
    return cookie_path.endswith("/") or request_path[len(cookie_path)] == "/"


def now_ms() -> int:
    """Return the time in LibreWolf's expiry unit."""
    return time.time_ns() // 1_000_000


def for_request(cookies: list[Cookie], url: str, now: int) -> list[Cookie]:
    """Return the cookies a request for url carries, in RFC 6265 order."""
    sent = [cookie for cookie in cookies if cookie.matches(url, now)]
    return sorted(sent, key=lambda cookie: (-len(cookie.path), cookie.created))


def for_host(cookies: Iterable[Cookie], url: str, now: int) -> list[Cookie]:
    """Return the unexpired cookies any path of url's host would carry."""
    host = urlsplit(url).hostname or ""
    return [
        c
        for c in cookies
        if c.expiry_ms > now
        and domain_match(host, c.host)
        and (not c.partition or partition_matches(c.partition, url))
    ]


def header(cookies: list[Cookie]) -> str:
    """Return the Cookie header value for the cookies, in order."""
    return "; ".join(cookie.pair for cookie in cookies)


def merge(preferred: Iterable[Cookie], other: Iterable[Cookie]) -> list[Cookie]:
    """Return both sets as one jar; a preferred cookie wins on the same key."""
    kept = {cookie.key: cookie for cookie in other}
    kept.update((cookie.key, cookie) for cookie in preferred)
    return list(kept.values())


def _default_path(path: str) -> str:
    """RFC 6265 section 5.1.4's default-path of a request path."""
    if not path.startswith("/") or path.count("/") == 1:
        return "/"
    return path[: path.rindex("/")]


def _expires(value: str) -> int | None:
    try:
        parsed = email.utils.parsedate_to_datetime(value)
    except TypeError, ValueError, IndexError:
        return None
    return int(parsed.timestamp() * 1000)


def parse_set_cookie(line: str, url: str, now: int) -> Cookie | None:  # noqa: C901, PLR0912
    """Parse one Set-Cookie value received for url, per RFC 6265 section 5.2.

    None when the browser would ignore it. A cookie whose expiry has passed
    is returned too: storing it deletes the cookie it replaces.
    """
    pair, _, attributes = line.partition(";")
    name, has_name, value = pair.partition("=")
    name, value = (name.strip(), value.strip()) if has_name else ("", name.strip())
    if (not name and not value) or _UNSENDABLE.intersection(name + value):
        return None
    parts = urlsplit(url)
    request_host = (parts.hostname or "").lower()
    host, path = request_host, _default_path(parts.path or "/")
    expiry: int | None = None
    max_age: int | None = None
    secure = http_only = partitioned = False
    same_site = SAME_SITE_UNSET
    for attribute in attributes.split(";"):
        key, _, raw = attribute.partition("=")
        key, raw = key.strip().lower(), raw.strip()
        if key == "expires":
            expiry = _expires(raw)
        elif key == "max-age" and _MAX_AGE.fullmatch(raw):
            max_age = int(raw)
        elif key == "domain" and raw:
            domain = raw.removeprefix(".").lower()
            if not domain_match(request_host, f".{domain}") or (
                _is_ip(request_host) and domain != request_host
            ):
                return None
            host = request_host if _is_ip(request_host) else f".{domain}"
        elif key == "path" and raw.startswith("/"):
            path = raw
        elif key == "secure":
            secure = True
        elif key == "httponly":
            http_only = True
        elif key == "partitioned":
            partitioned = True
        elif key == "samesite":
            same_site = {
                "none": SAME_SITE_NONE,
                "lax": SAME_SITE_LAX,
                "strict": SAME_SITE_STRICT,
            }.get(raw.lower(), SAME_SITE_UNSET)
    if (secure or partitioned) and parts.scheme != "https":
        return None
    if max_age is not None:
        expiry = now + max_age * 1000 if max_age > 0 else 0
    site = f"({parts.scheme},{request_host})"
    return Cookie(
        name,
        value,
        host,
        path,
        SESSION_EXPIRY_MS if expiry is None else expiry,
        secure,
        now,
        http_only=http_only,
        same_site=same_site,
        partition=site if partitioned and secure else "",
        session=expiry is None,
    )


def apply(
    cookies: Iterable[Cookie], url: str, set_cookies: Iterable[str], now: int
) -> list[Cookie]:
    """Return the jar after a response for url set its cookies, in order."""
    jar = {cookie.key: cookie for cookie in cookies}
    for line in set_cookies:
        cookie = parse_set_cookie(line, url, now)
        if cookie is None:
            continue
        old = jar.get(cookie.key)
        if old is not None:
            cookie = replace(cookie, created=old.created)
        jar[cookie.key] = cookie
    return [cookie for cookie in jar.values() if cookie.expiry_ms > now]
