# Copyright (c) 2026 Bad3r
"""Cookie matching per RFC 6265, the snapshot, and the browser's jar."""

import shutil
import sqlite3
import tempfile
import unittest
import unittest.mock
from pathlib import Path

from browser_fetch import cookies as jar

NOW = 1_800_000_000_000
LATER = NOW + 86_400_000
# The columns of LibreWolf 159's moz_cookies (schema version 17).
SCHEMA = """
create table moz_cookies (
  id integer primary key, originAttributes text not null default '', name text,
  value text, host text, path text, expiry integer, lastAccessed integer,
  creationTime integer, isSecure integer, isHttpOnly integer,
  inBrowserElement integer default 0, sameSite integer default 0,
  schemeMap integer default 0, isPartitionedAttributeSet integer default 0,
  updateTime integer,
  constraint moz_uniqueid unique (name, host, path, originAttributes)
)
"""


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


class MatchTest(unittest.TestCase):
    """Which cookies a request carries."""

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
        """A Secure cookie is never sent over http."""
        cookies = [cookie("s", "example.org", secure=True), cookie("plain", "example.org")]
        self.assertEqual(names(jar.for_request(cookies, "http://example.org/", NOW)), ["plain"])
        self.assertEqual(
            names(jar.for_request(cookies, "https://example.org/", NOW)), ["s", "plain"]
        )

    def test_expiry(self) -> None:
        """An expired cookie, in LibreWolf's milliseconds, is not sent."""
        cookies = [
            cookie("old", "example.org", expiry=NOW - 1),
            cookie("now", "example.org", expiry=NOW),
        ]
        self.assertEqual(jar.for_request(cookies, "https://example.org/", NOW), [])

    def test_order(self) -> None:
        """Longer paths come first, then earlier creation."""
        cookies = [
            cookie("late", "example.org", created=3),
            cookie("deep", "example.org", path="/a/b", created=9),
            cookie("early", "example.org", created=2),
        ]
        sent = jar.for_request(cookies, "https://example.org/a/b/c", NOW)
        self.assertEqual(names(sent), ["deep", "early", "late"])
        self.assertEqual(jar.header(sent), "deep=v-deep; early=v-early; late=v-late")

    def test_nameless_cookie(self) -> None:
        """A cookie without a name is sent as its value alone."""
        self.assertEqual(jar.header([cookie("", "example.org")]), "v-")

    def test_idn_hosts_match_their_a_labels(self) -> None:
        """Gecko stores an IDN host as A-labels, which the checked URL carries too."""
        from browser_fetch import urls  # noqa: PLC0415

        cookies = [cookie("idn", "xn--bcher-kva.example")]
        url = urls.check_url("https://bücher.example/")
        self.assertEqual(names(jar.for_request(cookies, url, NOW)), ["idn"])

    def test_for_host_ignores_path_and_scheme(self) -> None:
        """The browser's jar holds the host's cookies of every path."""
        cookies = [
            cookie("docs", "example.org", path="/docs", secure=True),
            cookie("other", "other.org"),
            cookie("old", "example.org", expiry=NOW),
        ]
        self.assertEqual(names(jar.for_host(cookies, "https://example.org/", NOW)), ["docs"])


class DatabaseTest(unittest.TestCase):
    """Reading a Gecko cookie database."""

    def setUp(self) -> None:
        """Create a profile whose database holds every kind of cookie row."""
        self.tmp = Path(tempfile.mkdtemp(prefix="browser-fetch-test-"))
        self.profile = self.tmp / "profile"
        self.profile.mkdir()
        db = sqlite3.connect(self.profile / jar.DB_NAME)
        db.execute(SCHEMA)
        db.execute("pragma user_version = 17")
        rows = [
            ("", "plain", "1", "example.org", 0),
            ("", "chipsdefault", "2", "example.org", 1),
            ("^partitionKey=%28https%2Cexample.org%29", "chipsown", "3", "example.org", 1),
            ("^partitionKey=%28https%2Cexample.org%29", "unflagged", "4", "example.org", 0),
            ("^partitionKey=%28https%2Cother.org%29", "foreign", "5", "example.org", 1),
            ("^userContextId=1", "container", "6", "example.org", 0),
            ("^firstPartyDomain=example.org", "fpi", "7", "example.org", 0),
            ("^privateBrowsingId=1", "private", "8", "example.org", 0),
            (
                "^partitionKey=%28https%2Cexample.org%29&userContextId=1",
                "both",
                "9",
                "example.org",
                1,
            ),
            ("", "bad", "a;b", "example.org", 0),
            ("", "crlf", "a\r\nX: y", "example.org", 0),
        ]
        db.executemany(
            "insert into moz_cookies (originAttributes, name, value, host, path, expiry,"
            " lastAccessed, creationTime, isSecure, isHttpOnly, isPartitionedAttributeSet)"
            " values (?, ?, ?, ?, '/', ?, 1, 1, 1, 0, ?)",
            [(o, n, v, h, LATER, p) for o, n, v, h, p in rows],
        )
        db.commit()
        db.close()

    def tearDown(self) -> None:
        """Remove the profile."""
        shutil.rmtree(self.tmp)

    def test_jars_firefox_sends(self) -> None:
        """The unpartitioned jar, flag or not, and CHIPS cookies of the site's own partition.

        Gecko's CookieService asks both jars on a top-level request and takes
        only Partitioned cookies from the partition; containers, first-party
        isolation and private browsing are other jars.
        """
        into = self.tmp / "work"
        into.mkdir()
        cookies = jar.read(jar.snapshot(self.profile, into))
        sent = names(jar.for_request(cookies, "https://example.org/", NOW))
        self.assertEqual(sorted(sent), ["chipsdefault", "chipsown", "plain"])
        self.assertEqual(
            sorted(names(jar.for_request(cookies, "https://www.example.org/", NOW))), []
        )

    def test_partition_is_the_top_level_site(self) -> None:
        """A partition matches its site and the site's subdomains, on its scheme and port."""
        self.assertTrue(jar.partition_matches("(https,example.org)", "https://a.example.org/"))
        self.assertFalse(jar.partition_matches("(https,example.org)", "https://other.org/"))
        self.assertFalse(jar.partition_matches("(https,example.org)", "http://example.org/"))
        self.assertFalse(jar.partition_matches("(https,example.org)", "https://example.org:8443/"))
        self.assertTrue(
            jar.partition_matches("(https,example.org,8443)", "https://example.org:8443/")
        )

    def test_snapshot_takes_the_wal(self) -> None:
        """Rows still in the WAL reach the snapshot."""
        db = sqlite3.connect(self.profile / jar.DB_NAME)
        db.execute("pragma journal_mode = wal")
        db.execute("pragma wal_autocheckpoint = 0")
        db.execute(
            "insert into moz_cookies (originAttributes, name, value, host, path, expiry,"
            " creationTime, isSecure) values ('', 'walrow', 'w', 'example.org', '/', ?, 2, 0)",
            (LATER,),
        )
        db.commit()
        self.assertTrue((self.profile / f"{jar.DB_NAME}-wal").stat().st_size > 0)
        into = self.tmp / "work"
        into.mkdir()
        copy = jar.snapshot(self.profile, into)
        db.close()
        self.assertIn("walrow", names(jar.read(copy)))

    def test_a_wal_removed_during_the_copy_is_retried(self) -> None:
        """A WAL that LibreWolf removes after it was seen restarts the snapshot."""
        db = sqlite3.connect(self.profile / jar.DB_NAME)
        db.execute("pragma journal_mode = wal")
        db.execute("pragma wal_autocheckpoint = 0")
        db.execute(
            "insert into moz_cookies (originAttributes, name, value, host, path, expiry,"
            " creationTime, isSecure) values ('', 'walrow', 'w', 'example.org', '/', ?, 2, 0)",
            (LATER,),
        )
        db.commit()
        real_copy = shutil.copyfile
        calls: list[str] = []

        def checkpoint_then_copy(source: Path, target: Path) -> Path:
            calls.append(Path(source).name)
            if len(calls) == 1:
                db.execute("pragma wal_checkpoint(truncate)")
                db.execute("pragma journal_mode = delete")
            return real_copy(source, target)

        into = self.tmp / "work"
        into.mkdir()
        try:
            with unittest.mock.patch.object(jar.shutil, "copyfile", checkpoint_then_copy):
                copy = jar.snapshot(self.profile, into)
        finally:
            db.close()
        self.assertEqual(calls, [f"{jar.DB_NAME}-wal", jar.DB_NAME])
        self.assertIn("walrow", names(jar.read(copy)))

    def test_a_database_removed_during_the_copy_is_no_database(self) -> None:
        """A database removed mid-copy reports a missing database, not a retry loop."""
        db = self.profile / jar.DB_NAME

        def remove_then_copy(source: Path, _target: Path) -> Path:
            db.unlink()
            raise FileNotFoundError(source)

        with (
            unittest.mock.patch.object(jar.shutil, "copyfile", remove_then_copy),
            self.assertRaisesRegex(jar.CookieError, "no readable cookie database"),
        ):
            jar.snapshot(self.profile, self.tmp)

    def test_missing_database(self) -> None:
        """A profile without a cookie database is an error."""
        with self.assertRaisesRegex(jar.CookieError, "no readable"):
            jar.snapshot(self.tmp, self.tmp)


URL = "https://www.example.org/a/b"


class SetCookieTest(unittest.TestCase):
    """Response cookies, per RFC 6265 section 5.2, for the rest of one fetch."""

    def test_host_only_and_default_path(self) -> None:
        """Without attributes a cookie is host-only, at the request's directory."""
        parsed = jar.parse_set_cookie("a=1", URL, NOW)
        if parsed is None:
            self.fail("the cookie was ignored")
        self.assertEqual(
            (parsed.host, parsed.path, parsed.session), ("www.example.org", "/a", True)
        )

    def test_domain_attribute(self) -> None:
        """A Domain the host lies in makes a domain cookie; another domain is ignored."""
        parsed = jar.parse_set_cookie("a=1; Domain=.Example.org; Path=/", URL, NOW)
        if parsed is None:
            self.fail("the cookie was ignored")
        self.assertEqual((parsed.host, parsed.path), (".example.org", "/"))
        self.assertIsNone(jar.parse_set_cookie("a=1; Domain=other.org", URL, NOW))

    def test_nameless(self) -> None:
        """A pair without "=" is a nameless cookie, sent as its value alone."""
        parsed = jar.parse_set_cookie("token123; Path=/", URL, NOW)
        if parsed is None:
            self.fail("the cookie was ignored")
        self.assertEqual(jar.header([parsed]), "token123")

    def test_attributes(self) -> None:
        """Max-Age sets the expiry, and the flags are kept."""
        parsed = jar.parse_set_cookie(
            "a=1; Max-Age=60; Secure; HttpOnly; SameSite=Strict", URL, NOW
        )
        if parsed is None:
            self.fail("the cookie was ignored")
        self.assertEqual(parsed.expiry_ms, NOW + 60_000)
        self.assertEqual(
            (parsed.secure, parsed.http_only, parsed.same_site),
            (True, True, jar.SAME_SITE_STRICT),
        )

    def test_apply_replaces_and_deletes(self) -> None:
        """A newer value replaces the cookie; Max-Age=0 removes it."""
        start = jar.apply([], URL, ["a=1; Path=/", "b=2; Path=/"], NOW)
        later = jar.apply(start, URL, ["a=3; Path=/", "b=; Path=/; Max-Age=0"], NOW)
        self.assertEqual(jar.header(later), "a=3")

    def test_merge_prefers_the_first(self) -> None:
        """On the same name, host and path, the preferred jar's cookie is the one kept."""
        mine = jar.Cookie(
            "cf_clearance", "camoufox", ".example.org", "/", LATER, secure=True, created=5
        )
        theirs = jar.Cookie(
            "cf_clearance", "librewolf", ".example.org", "/", LATER, secure=True, created=1
        )
        other = jar.Cookie("sid", "s", ".example.org", "/", LATER, secure=True, created=1)
        merged = jar.merge([mine], [theirs, other])
        self.assertEqual(
            sorted((c.name, c.value) for c in merged),
            [("cf_clearance", "camoufox"), ("sid", "s")],
        )


class ProfileTest(unittest.TestCase):
    """Which profile profiles.ini names as the default."""

    def test_install_default_wins(self) -> None:
        """An Install section's Default names the profile."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "profiles.ini").write_text(
                "[Profile0]\nName=a\nPath=a.default\nDefault=1\n\n[InstallABC]\nDefault=b.main\n"
            )
            self.assertEqual(jar.default_profile(root), root / "b.main")

    def test_no_ini(self) -> None:
        """A missing profiles.ini is an error."""
        with tempfile.TemporaryDirectory() as tmp, self.assertRaises(jar.CookieError):
            jar.default_profile(Path(tmp))
