# Copyright (c) 2026 Bad3r
"""Camoufox's cookie jar against Gecko's rules (netwerk/cookie/, Firefox 158.0.1).

Each expected value cites the Gecko code or the RFC it comes from.
"""

import sqlite3
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path
from typing import Any

from browser_fetch import cookies as jar

NOW = 1_800_000_000_000
LATER = NOW + 86_400_000
# A response time, in microseconds.
NOW_US = NOW * 1000
URL = "https://www.example.org/a/b"
HOUR_MS = 3_600_000
# CreateTableWorker in CookiePersistentStorage.cpp, the table of schema 17.
SCHEMA = jar.CREATE_TABLE


def cookie(  # noqa: PLR0913 - one field per cookie attribute under test
    name: str,
    host: str,
    *,
    path: str = "/",
    secure: bool = False,
    expiry: int = LATER,
    created: int = 1,
) -> jar.Cookie:
    """Return a cookie with a value derived from its name."""
    return jar.Cookie(name, f"v-{name}", host, path, expiry, secure, created)


def names(cookies: list[jar.Cookie]) -> list[str]:
    """Return the cookies' names in order."""
    return [c.name for c in cookies]


def parsed(line: str, url: str = URL, now: int = NOW_US, date: str | None = None) -> jar.Cookie:
    """Parse a Set-Cookie value that Gecko accepts."""
    result = jar.parse_set_cookie(line, url, now, date)
    if result is None:
        msg = f"Gecko accepts {line!r}"
        raise AssertionError(msg)
    return result


class FreshClock(unittest.TestCase):
    """Each test starts the unique creation clock afresh, as at browser start."""

    def setUp(self) -> None:
        """Reset the clock that keeps creation times unique, before and after the test."""
        jar.CREATION.last = 0
        self.addCleanup(setattr, jar.CREATION, "last", 0)


def rows(database: Path) -> list[dict[str, Any]]:
    """Every row of moz_cookies, every column by name."""
    connection = sqlite3.connect(database)
    connection.row_factory = sqlite3.Row
    try:
        return [dict(row) for row in connection.execute("SELECT * FROM moz_cookies ORDER BY id")]
    finally:
        connection.close()


def pragma(database: Path, name: str) -> object:
    """One PRAGMA's value."""
    connection = sqlite3.connect(database)
    try:
        return connection.execute(f"PRAGMA {name}").fetchone()[0]
    finally:
        connection.close()


class MatchTest(unittest.TestCase):
    """Which cookies a request carries (RFC 6265 section 5.4, CookieService::GetCookiesForURI)."""

    def test_host_only_and_domain(self) -> None:
        """Host-only cookies stay on their host; domain cookies reach subdomains."""
        cookies = [cookie("host", "example.org"), cookie("dom", ".example.org")]
        self.assertEqual(
            names(jar.for_request(cookies, "https://example.org/", NOW)), ["host", "dom"]
        )
        self.assertEqual(names(jar.for_request(cookies, "https://a.example.org/", NOW)), ["dom"])
        self.assertEqual(names(jar.for_request(cookies, "https://badexample.org/", NOW)), [])
        self.assertEqual(
            names(jar.for_request(cookies, "https://EXAMPLE.org/", NOW)), ["host", "dom"]
        )

    def test_ip_hosts_take_no_domain_cookies_by_suffix(self) -> None:
        """A domain cookie never matches an IP address by suffix."""
        cookies = [cookie("dom", ".0.0.1")]
        self.assertEqual(jar.for_request(cookies, "https://127.0.0.1/", NOW), [])

    def test_path(self) -> None:
        """A cookie path matches itself and paths below it at a slash."""
        cookies = [cookie("docs", "example.org", path="/docs"), cookie("root", "example.org")]
        self.assertEqual(
            names(jar.for_request(cookies, "https://example.org/docs", NOW)), ["docs", "root"]
        )
        self.assertEqual(
            names(jar.for_request(cookies, "https://example.org/docs/a", NOW)), ["docs", "root"]
        )
        self.assertEqual(
            names(jar.for_request(cookies, "https://example.org/docsx", NOW)), ["root"]
        )
        self.assertEqual(names(jar.for_request(cookies, "https://example.org", NOW)), ["root"])

    def test_trailing_slash_path(self) -> None:
        """A cookie path ending in a slash matches everything under it."""
        cookies = [cookie("p", "example.org", path="/a/")]
        self.assertEqual(names(jar.for_request(cookies, "https://example.org/a/b", NOW)), ["p"])
        self.assertEqual(jar.for_request(cookies, "https://example.org/a", NOW), [])

    def test_secure(self) -> None:
        """A Secure cookie is never sent over http to a host other than loopback."""
        cookies = [cookie("s", "example.org", secure=True), cookie("plain", "example.org")]
        self.assertEqual(names(jar.for_request(cookies, "http://example.org/", NOW)), ["plain"])
        self.assertEqual(
            names(jar.for_request(cookies, "https://example.org/", NOW)), ["s", "plain"]
        )

    def test_secure_to_loopback_over_http(self) -> None:
        """Loopback is potentially trustworthy, so http to it sends Secure cookies as Gecko does."""
        for host in ("localhost", "app.localhost", "127.0.0.1", "127.8.9.10", "::1"):
            with self.subTest(host=host):
                named = f"[{host}]" if ":" in host else host
                url = f"http://{named}:8080/"
                self.assertEqual(
                    names(jar.for_request([cookie("s", named, secure=True)], url, NOW)), ["s"]
                )
        for host in ("10.0.0.1", "::ffff:127.0.0.1", "localhost.example"):
            with self.subTest(host=host):
                named = f"[{host}]" if ":" in host else host
                url = f"http://{named}/"
                self.assertEqual(jar.for_request([cookie("s", named, secure=True)], url, NOW), [])

    def test_ipv6_hosts_are_bracketed(self) -> None:
        """Gecko names an IPv6 host in brackets, set and sent alike (GetHostOrIPv6WithBrackets)."""
        url = "http://[::1]:8080/app"
        received = parsed("a=1; Max-Age=60", url)
        self.assertEqual(received.host, "[::1]")
        self.assertEqual(names(jar.for_request([received], url, NOW_US // 1000)), ["a"])
        self.assertEqual(jar.for_request([cookie("bare", "::1")], url, NOW), [])
        self.assertEqual(parsed("b=1; Domain=[::1]", url).host, "[::1]")
        self.assertIsNone(jar.parse_set_cookie("b=1; Domain=::1", url, NOW_US))

    def test_expiry(self) -> None:
        """A cookie whose expiry, in milliseconds, is not after now is not sent (IsExpired)."""
        cookies = [
            cookie("old", "example.org", expiry=NOW - 1),
            cookie("now", "example.org", expiry=NOW),
        ]
        self.assertEqual(jar.for_request(cookies, "https://example.org/", NOW), [])

    def test_order(self) -> None:
        """Longer paths come first, then earlier creation (CompareCookiesForSending)."""
        cookies = [
            cookie("late", "example.org", created=3),
            cookie("deep", "example.org", path="/a/b", created=9),
            cookie("early", "example.org", created=2),
        ]
        sent = jar.for_request(cookies, "https://example.org/a/b/c", NOW)
        self.assertEqual(names(sent), ["deep", "early", "late"])
        self.assertEqual(jar.header(sent), "deep=v-deep; early=v-early; late=v-late")

    def test_valueless_cookie(self) -> None:
        """A named cookie with no value is sent as "name=" (ComposeCookieString)."""
        flag = jar.Cookie("flag", "", "example.org", "/", LATER, secure=False, created=1)
        self.assertEqual(jar.header([flag]), "flag=")

    def test_idn_hosts_match_their_a_labels(self) -> None:
        """Gecko stores an IDN host as A-labels, which the checked URL carries too."""
        from browser_fetch import urls  # noqa: PLC0415

        cookies = [cookie("idn", "xn--bcher-kva.example")]
        url = urls.check_url("https://bücher.example/")
        self.assertEqual(names(jar.for_request(cookies, url, NOW)), ["idn"])

    def test_partitioned_cookie_goes_to_its_own_site_only(self) -> None:
        """A CHIPS cookie goes with a top-level request whose site is its partition's.

        The site is the scheme and registrable domain, with no port
        (MakeTopLevelInfo), so a subdomain and another port are the same site.
        """
        chips = replace(
            cookie("chips", ".example.org", secure=True), partition="(https,example.org)"
        )
        for url, sent in (
            ("https://example.org/", True),
            ("https://www.example.org:8443/", True),
            ("https://other.org/", False),
            ("http://example.org/", False),
        ):
            with self.subTest(url=url):
                self.assertEqual(bool(jar.for_request([chips], url, NOW)), sent)


class SiteTest(unittest.TestCase):
    """The site a partition key names (OriginAttributes::SetPartitionKey)."""

    def test_partition_key(self) -> None:
        """The registrable domain by the Public Suffix List, else the host itself."""
        for url, key in (
            ("https://a.b.example.co.uk/x", "(https,example.co.uk)"),
            ("https://example.org:8443/", "(https,example.org)"),
            ("https://user.github.io/", "(https,user.github.io)"),
            ("https://github.io/", "(https,github.io)"),
            ("https://93.184.215.14/", "(https,93.184.215.14)"),
        ):
            with self.subTest(url=url):
                self.assertEqual(jar.partition_key(url), key)

    def test_origin_attributes(self) -> None:
        """CreateSuffix: ":" becomes "+", then URLParams percent-encodes the value.

        The first form is a row Gecko 159 wrote; the second shows the
        sanitized colon of an IPv6 site.
        """
        self.assertEqual(
            jar.origin_attributes("(https,example.org)"),
            "^partitionKey=%28https%2Cexample.org%29",
        )
        self.assertEqual(
            jar.origin_attributes("(https,[2001:db8::1])"),
            "^partitionKey=%28https%2C%5B2001%2Bdb8%2B%2B1%5D%29",
        )
        self.assertEqual(jar.origin_attributes(""), "")


class SetCookieTest(FreshClock):
    """Set-Cookie values of a top-level response, as CookieParser and CookieValidation take them."""

    def test_host_only_and_default_path(self) -> None:
        """Without attributes a cookie is host-only, at the request's directory, and session."""
        result = parsed("a=1")
        self.assertEqual(
            (result.host, result.path, result.session, result.expiry_ms),
            ("www.example.org", "/a", True, jar.SESSION_EXPIRY_MS),
        )

    def test_domain_attribute(self) -> None:
        """A Domain the host lies in makes a domain cookie, written with a leading dot.

        FixDomain lowercases it and drops one leading dot; CheckDomain wants
        it under the base domain and over the host.
        """
        self.assertEqual(parsed("a=1; Domain=.Example.org").host, ".example.org")
        self.assertEqual(parsed("a=1; Domain=www.example.org").host, ".www.example.org")
        for domain in ("other.org", "org", "a.www.example.org"):
            with self.subTest(domain=domain):
                self.assertIsNone(jar.parse_set_cookie(f"a=1; Domain={domain}", URL, NOW_US))

    def test_public_suffix_domain(self) -> None:
        """Domain=co.uk is refused, as the suffix has no base domain to lie under."""
        url = "https://www.example.co.uk/"
        self.assertIsNone(jar.parse_set_cookie("a=1; Domain=co.uk", url, NOW_US))
        self.assertEqual(parsed("a=1; Domain=example.co.uk", url).host, ".example.co.uk")

    def test_domain_on_an_address(self) -> None:
        """An address takes only its own Domain, and the cookie stays host-only."""
        url = "https://93.184.215.14/"
        self.assertEqual(parsed("a=1; Domain=93.184.215.14", url).host, "93.184.215.14")
        self.assertIsNone(jar.parse_set_cookie("a=1; Domain=184.215.14", url, NOW_US))

    def test_valueless(self) -> None:
        """A token without "=" is the name with an empty value; an empty name is refused.

        network.cookie.valueless_cookie is true in 158 (ParseAttributes),
        and CheckName then refuses an empty name.
        """
        flag = parsed("token123; Path=/")
        self.assertEqual((flag.name, flag.value), ("token123", ""))
        self.assertIsNone(jar.parse_set_cookie("=value", URL, NOW_US))

    def test_max_age(self) -> None:
        """Max-Age counts from the creation time, capped at 400 days (MaybeCapMaxAge)."""
        result = parsed("a=1; Max-Age=60")
        self.assertEqual(result.expiry_ms, result.created // 1000 + 60_000)
        self.assertFalse(result.session)
        capped = parsed("a=1; Max-Age=999999999999")
        self.assertEqual(capped.expiry_ms, capped.created // 1000 + 34_560_000_000)

    def test_max_age_wins_over_expires_unless_it_is_not_a_number(self) -> None:
        """Max-Age overrides Expires; one with a non-digit is ignored (ParseMaxAgeAttribute)."""
        expires = "Expires=Thu, 15 Jan 2027 09:00:00 GMT"
        five = parsed(f"a=1; {expires}; Max-Age=5")
        self.assertEqual(five.expiry_ms, five.created // 1000 + 5000)
        self.assertEqual(parsed(f"a=1; {expires}; Max-Age=5s").expiry_ms, NOW + HOUR_MS)

    def test_negative_max_age_is_expired(self) -> None:
        """A Max-Age starting with "-" expires the cookie at once."""
        self.assertTrue(parsed("a=1; Max-Age=-1").expired(NOW))
        self.assertTrue(parsed("a=; Max-Age=0").expired(NOW))

    def test_expires_follows_the_servers_clock(self) -> None:
        """Expires is moved by the gap between this clock and the Date header (GetExpiry).

        The server's clock is an hour behind: an Expires an hour after its
        Date is an hour after now here.
        """
        date = "Thu, 15 Jan 2027 07:00:00 GMT"
        result = parsed("a=1; Expires=Thu, 15 Jan 2027 08:00:00 GMT", date=date)
        self.assertEqual(result.expiry_ms, result.created // 1000 + HOUR_MS)

    def test_unparsable_expires_is_a_session_cookie(self) -> None:
        """An Expires PR_ParseTimeString cannot read leaves a session cookie."""
        self.assertTrue(parsed("a=1; Expires=soon").session)

    def test_expires_in_any_form_gecko_reads(self) -> None:
        """An asctime Expires, which RFC 6265 and PR_ParseTimeString both read, is persistent.

        Wed Jun 09 10:18:14 2027 is 1812536294 s after the epoch, in GMT
        since it names no zone (GetExpiry passes default_to_gmt).
        """
        result = parsed("a=1; Expires=Wed Jun 09 10:18:14 2027")
        self.assertEqual((result.session, result.expiry_ms), (False, 1_812_536_294_000))

    def test_attributes(self) -> None:
        """Secure, HttpOnly and SameSite are kept as nsICookie's values."""
        result = parsed("a=1; Max-Age=60; Secure; HttpOnly; SameSite=Strict")
        self.assertEqual(
            (result.secure, result.http_only, result.same_site),
            (True, True, jar.SAME_SITE_STRICT),
        )

    def test_same_site_values(self) -> None:
        """None 0, Lax 1, Strict 2, absent or unknown 256 (nsICookie.idl, Bug 1682450)."""
        for attribute, value in (
            ("; SameSite=None; Secure", 0),
            ("; SameSite=lax", 1),
            ("; SameSite=STRICT", 2),
            ("", 256),
            ("; SameSite=bogus", 256),
        ):
            with self.subTest(attribute=attribute):
                self.assertEqual(parsed(f"a=1{attribute}").same_site, value)

    def test_same_site_none_needs_secure(self) -> None:
        """network.cookie.sameSite.noneRequiresSecure refuses SameSite=None without Secure."""
        self.assertIsNone(jar.parse_set_cookie("a=1; SameSite=None", URL, NOW_US))

    def test_secure_needs_a_secure_origin(self) -> None:
        """A Secure cookie from http is refused (eRejectedSecureButNonHttps)."""
        self.assertIsNone(jar.parse_set_cookie("a=1; Secure", "http://example.org/", NOW_US))
        local = parsed("a=1; Secure", "http://localhost:8080/")
        self.assertTrue(local.secure)
        self.assertEqual(local.scheme_map, jar.SCHEME_HTTP)
        self.assertTrue(parsed("__Host-a=1; Secure; Path=/", "http://127.0.0.1/").secure)
        self.assertEqual(parsed("a=1", "http://example.org/").scheme_map, jar.SCHEME_HTTP)
        self.assertEqual(parsed("a=1").scheme_map, jar.SCHEME_HTTPS)

    def test_partitioned(self) -> None:
        """Partitioned needs Secure, and puts the cookie in the page's own site partition."""
        self.assertIsNone(jar.parse_set_cookie("a=1; Partitioned", URL, NOW_US))
        result = parsed("a=1; Secure; Partitioned")
        self.assertEqual(result.partition, "(https,example.org)")
        self.assertEqual(result.origin_attributes, "^partitionKey=%28https%2Cexample.org%29")

    def test_prefixes(self) -> None:
        """__Host- wants Secure, no Domain and Path=/ as sent; __Secure- wants Secure."""
        self.assertEqual(parsed("__Host-a=1; Secure; Path=/").path, "/")
        for line in (
            "__Host-a=1; Secure",
            "__host-a=1; Path=/",
            "__Host-a=1; Secure; Path=/; Domain=example.org",
            "__Secure-a=1",
            "__Http-a=1; Secure",
        ):
            with self.subTest(line=line):
                self.assertIsNone(jar.parse_set_cookie(line, URL, NOW_US))

    def test_invalid_characters(self) -> None:
        """A control character in an attribute refuses the cookie; ";" never reaches a value."""
        self.assertIsNone(jar.parse_set_cookie("a=1; Path=/\x01", URL, NOW_US))
        self.assertIsNone(jar.parse_set_cookie("a\x7f=1", URL, NOW_US))
        self.assertEqual(parsed("a=1;2").value, "1")

    def test_oversized(self) -> None:
        """Name and value over 4096 bytes refuse the cookie; an attribute over 1024 is ignored."""
        self.assertIsNone(jar.parse_set_cookie("a=" + "x" * 4096, URL, NOW_US))
        self.assertEqual(len(parsed("a=" + "x" * 4095).value), 4095)
        self.assertEqual(parsed("a=1; Path=/" + "p" * 1024).path, "/a")

    def test_later_attribute_wins(self) -> None:
        """A repeated Path, Domain, Expires or Max-Age takes the last one (CheckAttributeSize)."""
        self.assertEqual(parsed("a=1; Path=/x; Path=/y").path, "/y")

    def test_creation_times_are_unique(self) -> None:
        """Two cookies of one response never share a creation time (GenerateUniqueCreationTime)."""
        first, second = parsed("a=1"), parsed("b=1")
        self.assertLess(first.created, second.created)
        self.assertEqual((first.accessed, first.updated), (NOW_US, first.created))


class JarTest(FreshClock):
    """A fetch's responses applied to the jar, as CookieStorage::AddCookie applies them."""

    def stored(self, *cookies: jar.Cookie) -> jar.Jar:
        """A jar holding the given rows."""
        return jar.Jar.of(cookies)

    def test_replacement_keeps_the_creation_time(self) -> None:
        """A cookie replacing a live one keeps its creation time, for ordering."""
        old = replace(parsed("sid=old; Max-Age=600; Path=/"), created=5)
        cookies = self.stored(old)
        cookies.receive(URL, ["sid=new; Max-Age=600; Path=/"], NOW_US + 1000, None)
        (new,) = cookies.pending()
        self.assertEqual((new.value, new.created), ("new", 5))

    def test_deletion_shadows_the_stored_row(self) -> None:
        """A deletion of a stored cookie is a change, and the cookie is no longer sent."""
        cookies = self.stored(parsed("sid=old; Max-Age=600; Path=/"))
        cookies.receive(URL, ["sid=; Path=/; Max-Age=0"], NOW_US + 1000, None)
        self.assertEqual([c.name for c in cookies.pending()], ["sid"])
        self.assertEqual(jar.for_request(cookies.cookies(), URL, NOW + 1), [])

    def test_deletion_is_kept_whatever_the_view_holds(self) -> None:
        """An expired cookie is a deletion even with no live cookie of its key in sight.

        The fetch's view may lack a row the database holds, when a busy
        profile went unread; AddCookie removes whatever cookie the key has.
        """
        cookies = self.stored()
        cookies.receive(URL, ["sid=; Max-Age=0"], NOW_US, None)
        (deleted,) = cookies.pending()
        self.assertEqual((deleted.name, deleted.expired(NOW)), ("sid", True))

    def test_same_cookie_again_changes_nothing(self) -> None:
        """An identical cookie set within the stale threshold leaves the old one."""
        cookies = self.stored()
        line = "sid=1; Expires=Thu, 15 Jan 2027 09:00:00 GMT; Path=/"
        cookies.receive(URL, [line], NOW_US, None)
        cookies.unsaved.clear()
        cookies.receive(URL, [line], NOW_US + 1_000_000, None)
        self.assertEqual(cookies.pending(), [])

    def test_received_cookies_win_and_reach_the_next_request(self) -> None:
        """A cookie a response set is sent with the next request, over the stored one."""
        cookies = self.stored(replace(parsed("sid=old; Max-Age=600; Path=/"), created=5))
        cookies.receive(URL, ["sid=new; Path=/"], NOW_US + 1000, None)
        self.assertEqual(jar.header(jar.for_request(cookies.cookies(), URL, NOW + 2)), "sid=new")

    def test_http_leaves_a_secure_cookie_alone(self) -> None:
        """Over http, no non-Secure cookie replaces or deletes a Secure one (FindSecureCookie).

        Same name, hosts domain-matching either way, and the Secure cookie's
        path covering the new one's; https and loopback origins may.
        """
        secure = cookie("sid", "www.example.org", path="/a/", secure=True)
        blocked = {
            "replace": ("http://www.example.org/", "sid=x; Path=/a/"),
            "delete": ("http://www.example.org/", "sid=; Path=/a/; Max-Age=0"),
            "below its path": ("http://www.example.org/", "sid=x; Path=/a/b"),
            "domain over its host": (
                "http://www.example.org/",
                "sid=x; Path=/a/; Domain=example.org",
            ),
        }
        for case, (url, line) in blocked.items():
            with self.subTest(case=case):
                cookies = self.stored(secure)
                cookies.receive(url, [line], NOW_US + 1000, None)
                self.assertEqual(cookies.pending(), [])
                self.assertEqual(cookies.get(secure.key), secure)
        allowed = {
            "https": ("https://www.example.org/", "sid=x; Path=/a/"),
            "other name": ("http://www.example.org/", "other=x; Path=/a/"),
            "outside its path": ("http://www.example.org/", "sid=x; Path=/"),
            "other host": ("http://example.org/", "sid=x; Path=/a/"),
        }
        for case, (url, line) in allowed.items():
            with self.subTest(case=case):
                cookies = self.stored(secure)
                cookies.receive(url, [line], NOW_US + 1000, None)
                self.assertEqual(len(cookies.pending()), 1)

    def test_secure_domain_cookie_covers_its_subdomains(self) -> None:
        """A Secure domain cookie blocks an http host cookie of a subdomain."""
        cookies = self.stored(cookie("sid", ".example.org", secure=True))
        cookies.receive("http://a.example.org/", ["sid=x; Path=/"], NOW_US + 1000, None)
        self.assertEqual(cookies.pending(), [])

    def test_loopback_over_http_may_replace_a_secure_cookie(self) -> None:
        """Loopback is potentially trustworthy, so AddCookie lets it overlay a Secure cookie."""
        cookies = self.stored(cookie("sid", "localhost", secure=True))
        cookies.receive("http://localhost:8080/", ["sid=x; Path=/"], NOW_US + 1000, None)
        self.assertEqual([c.value for c in cookies.pending()], ["x"])

    def test_expired_secure_cookie_blocks_nothing(self) -> None:
        """A Secure cookie past its expiry guards nothing: RFC 6265bis section 5.7 evicts it.

        Gecko blocks on one only until a purge drops it, which depends on timing.
        """
        cookies = self.stored(cookie("sid", "www.example.org", secure=True, expiry=NOW - 1))
        cookies.receive("http://www.example.org/", ["sid=x; Path=/"], NOW_US + 1000, None)
        self.assertEqual([c.value for c in cookies.pending()], ["x"])


class DatabaseTest(FreshClock):
    """cookies.sqlite at schema 17, written and read as Gecko does."""

    def setUp(self) -> None:
        """A profile directory without a database."""
        super().setUp()
        holder = tempfile.TemporaryDirectory(prefix="browser-fetch-test-")
        self.addCleanup(holder.cleanup)
        self.database = Path(holder.name) / "profile" / jar.DB_NAME

    def store(self, *cookies: jar.Cookie, now: int = NOW_US) -> int:
        """Write the cookies."""
        return jar.store(self.database, cookies, now)

    def test_new_database_is_geckos(self) -> None:
        """A database written first here has Gecko's version, table and page size."""
        self.store(parsed("a=1; Max-Age=60"))
        self.assertEqual(pragma(self.database, "user_version"), 17)
        self.assertEqual(pragma(self.database, "page_size"), 32768)
        connection = sqlite3.connect(self.database)
        try:
            sql = connection.execute(
                "SELECT sql FROM sqlite_master WHERE name = 'moz_cookies'"
            ).fetchone()[0]
        finally:
            connection.close()
        self.assertEqual(sql, SCHEMA)

    def test_row_roundtrip(self) -> None:
        """Every column of the row as Gecko's insert binds it, and the same cookie read back.

        expiry is in milliseconds, lastAccessed, creationTime and updateTime
        in microseconds (GetCookieFromRow); inBrowserElement keeps its default.
        """
        written = parsed(
            "sid=abc; Max-Age=3600; Domain=example.org; Path=/; Secure; HttpOnly; SameSite=Lax"
        )
        self.store(written)
        (row,) = rows(self.database)
        self.assertEqual(
            {k: v for k, v in row.items() if k != "id"},
            {
                "originAttributes": "",
                "name": "sid",
                "value": "abc",
                "host": ".example.org",
                "path": "/",
                "expiry": written.created // 1000 + 3_600_000,
                "lastAccessed": NOW_US,
                "creationTime": written.created,
                "isSecure": 1,
                "isHttpOnly": 1,
                "inBrowserElement": 0,
                "sameSite": 1,
                "schemeMap": 2,
                "isPartitionedAttributeSet": 0,
                "updateTime": written.created,
            },
        )
        self.assertEqual(jar.read(self.database), [written])

    def test_session_cookie_is_never_stored(self) -> None:
        """Gecko writes no session cookie (StoreCookie returns early on IsSession)."""
        self.assertEqual(self.store(parsed("s=1; Path=/")), 0)
        self.assertEqual(rows(self.database), [])

    def test_session_cookie_replacing_a_stored_one_removes_its_row(self) -> None:
        """Replacing a persistent cookie removes its row; the session cookie stays in memory."""
        self.store(parsed("s=1; Max-Age=600; Path=/"))
        cookies = jar.Jar.of(jar.read(self.database))
        cookies.receive(URL, ["s=2; Path=/"], NOW_US + 1000, None)
        self.store(*cookies.pending(), now=NOW_US + 1000)
        self.assertEqual(rows(self.database), [])

    def test_deletion_removes_the_row(self) -> None:
        """A Set-Cookie that expires the cookie deletes its row (RemoveCookieFromDB)."""
        self.store(parsed("d=1; Max-Age=600; Path=/"), parsed("keep=1; Max-Age=600; Path=/"))
        cookies = jar.Jar.of(jar.read(self.database))
        cookies.receive(URL, ["d=; Max-Age=0; Path=/"], NOW_US + 1000, None)
        self.store(*cookies.pending(), now=NOW_US + 1000)
        self.assertEqual([row["name"] for row in rows(self.database)], ["keep"])

    def test_deletion_reaches_a_row_the_fetch_never_read(self) -> None:
        """A deletion received while the jar went unread removes the row all the same."""
        self.store(parsed("sid=secret; Max-Age=600; Path=/"), parsed("keep=1; Max-Age=600; Path=/"))
        cookies = jar.Jar.of([])
        cookies.receive(URL, ["sid=; Max-Age=0; Path=/"], NOW_US + 1000, None)
        self.assertEqual(self.store(*cookies.pending(), now=NOW_US + 1000), 1)
        self.assertEqual([row["name"] for row in rows(self.database)], ["keep"])

    def test_deleting_an_absent_row_changes_nothing(self) -> None:
        """With no row of the key, a deletion leaves the table as it was ("already expired")."""
        self.store(parsed("keep=1; Max-Age=600; Path=/"))
        before = rows(self.database)
        cookies = jar.Jar.of(jar.read(self.database))
        cookies.receive(URL, ["sid=; Max-Age=0; Path=/"], NOW_US + 1000, None)
        self.assertEqual(self.store(*cookies.pending(), now=NOW_US + 1000), 0)
        self.assertEqual(rows(self.database), before)

    def test_recreation_after_a_deletion_is_a_new_cookie(self) -> None:
        """A cookie deleted and set again before the write gets a fresh creation time.

        AddCookie removes the old cookie before the new one comes, so the new
        one is created now, whether both came in one response or the write
        waited for a later one.
        """
        old = replace(parsed("sid=old; Max-Age=600; Path=/"), created=5)
        deletion, again = "sid=; Max-Age=0; Path=/", "sid=new; Max-Age=600; Path=/"
        for responses in ([[deletion, again]], [[deletion], [again]]):
            with self.subTest(responses=responses):
                self.database.unlink(missing_ok=True)
                self.store(old)
                cookies = jar.Jar.of(jar.read(self.database))
                for at, lines in enumerate(responses, 1):
                    cookies.receive(URL, lines, NOW_US + at * 1000, None)
                created = cookies.changed[old.key].created
                self.store(*cookies.pending(), now=NOW_US + 5000)
                (row,) = rows(self.database)
                self.assertEqual((row["value"], row["creationTime"]), ("new", created))
                self.assertGreater(created, old.created)

    def test_replacement_on_the_unique_key(self) -> None:
        """One row per name, host, path and originAttributes: a new value replaces the row.

        The creation time stays the first cookie's (AddCookie); updateTime
        and lastAccessed are the new one's. Another path is another row.
        """
        first = parsed("r=1; Max-Age=600; Path=/")
        self.store(first)
        later = NOW_US + 5_000_000
        second = parsed("r=2; Max-Age=600; Path=/", now=later)
        self.store(second, parsed("r=3; Max-Age=600; Path=/x", now=later), now=later)
        replaced = [row for row in rows(self.database) if row["path"] == "/"]
        self.assertEqual(len(rows(self.database)), 2)
        self.assertEqual(
            [(r["value"], r["creationTime"], r["updateTime"], r["lastAccessed"]) for r in replaced],
            [("2", first.created, second.created, later)],
        )

    def test_identical_cookie_leaves_the_row(self) -> None:
        """The same cookie again within the stale threshold changes nothing."""
        line = "i=1; Expires=Thu, 15 Jan 2027 09:00:00 GMT; Path=/"
        self.store(parsed(line))
        before = rows(self.database)
        self.assertEqual(self.store(parsed(line, now=NOW_US + 1_000_000)), 0)
        self.assertEqual(rows(self.database), before)

    def test_partitioned_row(self) -> None:
        """A Partitioned cookie of a top-level page is keyed by the page's site partition.

        It has its own row beside an unpartitioned cookie of the same name,
        host and path, and is read back for that site only.
        """
        self.store(
            parsed("p=chips; Max-Age=600; Path=/; Secure; Partitioned"),
            parsed("p=plain; Max-Age=600; Path=/; Secure"),
        )
        by_value = {row["value"]: row for row in rows(self.database)}
        self.assertEqual(
            (by_value["chips"]["originAttributes"], by_value["chips"]["isPartitionedAttributeSet"]),
            ("^partitionKey=%28https%2Cexample.org%29", 1),
        )
        self.assertEqual(
            (by_value["plain"]["originAttributes"], by_value["plain"]["isPartitionedAttributeSet"]),
            ("", 0),
        )
        read = jar.read(self.database)
        self.assertEqual(
            sorted(c.value for c in jar.for_request(read, URL, NOW + 1)), ["chips", "plain"]
        )
        self.assertEqual(
            [c.value for c in jar.for_request(read, "https://www.other.org/", NOW + 1)], []
        )

    def test_other_schema_versions_are_refused(self) -> None:
        """Neither read nor write touches a database at another version, which stays as it was."""
        self.store(parsed("a=1; Max-Age=600"))
        for version in (16, 18, 0):
            with self.subTest(version=version):
                connection = sqlite3.connect(self.database)
                connection.execute(f"PRAGMA user_version = {version}")
                connection.commit()
                connection.close()
                before = rows(self.database)
                with self.assertRaisesRegex(jar.CookieError, f"schema version {version}"):
                    self.store(parsed("b=1; Max-Age=600"))
                with self.assertRaisesRegex(jar.CookieError, f"schema version {version}"):
                    jar.read(self.database)
                self.assertEqual(rows(self.database), before)
                self.assertEqual(pragma(self.database, "user_version"), version)

    def test_empty_file_gets_the_table(self) -> None:
        """An empty database file gets Gecko's table, as TryInitDB creates it."""
        self.database.parent.mkdir()
        self.database.touch()
        self.assertEqual(jar.read(self.database), [])
        self.store(parsed("a=1; Max-Age=600"))
        self.assertEqual(pragma(self.database, "user_version"), 17)
        self.assertEqual(len(rows(self.database)), 1)

    def test_no_connection_outlives_a_write(self) -> None:
        """No -wal or -shm file is left: the last connection closed, so SQLite checkpointed."""
        self.store(parsed("a=1; Max-Age=600"))
        self.assertEqual(pragma(self.database, "journal_mode"), "wal")
        leftovers = [p.name for p in self.database.parent.iterdir() if p.name != jar.DB_NAME]
        self.assertEqual(leftovers, [])

    def test_rows_gecko_leaves_out(self) -> None:
        """The rows a top-level request reads, and those of other jars or Gecko drops.

        Gecko asks the unpartitioned jar and the site's partition, taking
        only Partitioned cookies from it (CookieService.cpp); Read() drops
        nameless rows and domain rows of a public suffix; a partition of a
        foreign ancestor (",f") is another site's.
        """
        self.store(parsed("seed=1; Max-Age=600"))
        connection = sqlite3.connect(self.database)
        key = "^partitionKey=%28https%2Cexample.org%29"
        connection.executemany(
            "INSERT INTO moz_cookies (originAttributes, name, value, host, path, expiry,"
            " lastAccessed, creationTime, isSecure, isHttpOnly, isPartitionedAttributeSet)"
            " VALUES (?, ?, 'v', ?, '/', ?, 1, 1, 1, 0, ?)",
            [
                (o, n, h, LATER, p)
                for o, n, h, p in (
                    ("", "plain", "example.org", 0),
                    (key, "chips", "example.org", 1),
                    (key, "unflagged", "example.org", 0),
                    ("^partitionKey=%28https%2Cexample.org%2Cf%29", "ancestor", "example.org", 1),
                    ("^partitionKey=%28https%2Cother.org%29", "foreign", "example.org", 1),
                    ("^userContextId=1", "container", "example.org", 0),
                    ("^firstPartyDomain=example.org", "fpi", "example.org", 0),
                    ("^privateBrowsingId=1", "private", "example.org", 0),
                    (f"{key}&userContextId=1", "both", "example.org", 1),
                    ("", "", "example.org", 0),
                    ("", "suffix", ".org", 0),
                    ("", "crlf", "example.org", 0),
                )
            ],
        )
        connection.execute("UPDATE moz_cookies SET value = 'a\r\nX: y' WHERE name = 'crlf'")
        connection.commit()
        connection.close()
        sent = jar.for_request(jar.read(self.database), "https://example.org/", NOW)
        self.assertEqual(sorted(names(sent)), ["chips", "plain"])

    def test_store_of_nothing_creates_nothing(self) -> None:
        """No change, no database."""
        self.assertEqual(self.store(), 0)
        self.assertFalse(self.database.exists())
