# Copyright (c) 2026 Bad3r
"""URL checks, preapproved locations and the redirect policy."""

import unittest

from browser_fetch import urls


class CheckUrlTest(unittest.TestCase):
    """Which URLs WebFetch takes, and the https upgrade."""

    def test_http_is_upgraded(self) -> None:
        """A plain http URL is requested over https, default port dropped."""
        self.assertEqual(urls.check_url("http://example.org/a?b=1"), "https://example.org/a?b=1")
        self.assertEqual(urls.check_url("http://example.org:80/"), "https://example.org/")
        self.assertEqual(urls.check_url("http://example.org:8080/"), "https://example.org:8080/")

    def test_https_is_kept(self) -> None:
        """An https URL passes unchanged."""
        self.assertEqual(urls.check_url("https://example.org/x#y"), "https://example.org/x#y")

    def test_rejected(self) -> None:
        """Credentials, other schemes, overlong URLs and bad ports are WebFetch's invalid URL."""
        for bad in (
            "https://user:pw@example.org/",
            "ftp://example.org/",
            "file:///etc/passwd",
            "https://example.org:99999/",
            "https://example.org/" + "a" * 2000,
        ):
            with self.subTest(bad=bad), self.assertRaisesRegex(urls.UrlError, "^Invalid URL$"):
                urls.check_url(bad)

    def test_dotless_host(self) -> None:
        """A host without a dot names the local-server alternative."""
        with self.assertRaisesRegex(urls.UrlError, "without a dot"):
            urls.check_url("http://localhost:8000/")

    def test_ipv6_literal_is_dotless(self) -> None:
        """An IPv6 literal is refused, as WebFetch's hostname dot check refuses it."""
        for literal in ("http://[::1]/", "http://[::ffff:127.0.0.1]/x", "https://[2001:db8::1]/"):
            with (
                self.subTest(literal=literal),
                self.assertRaisesRegex(urls.UrlError, "without a dot"),
            ):
                urls.check_url(literal)

    def test_hosts_are_serialized_as_the_url_standard_does(self) -> None:
        """Unicode names become A-labels, numeric hosts dotted quads, case folds."""
        self.assertEqual(
            urls.check_url("https://Bücher.example/a"), "https://xn--bcher-kva.example/a"
        )
        self.assertEqual(urls.check_url("http://0x7f.1/"), "https://127.0.0.1/")
        self.assertEqual(urls.check_url("https://EXAMPLE.org/"), "https://example.org/")
        with self.assertRaises(urls.UrlError):
            urls.check_url("https://1.2.3.999/")


class LocalTest(unittest.TestCase):
    """Hosts on this machine or a non-public network."""

    def test_local(self) -> None:
        """Loopback, private, link-local, shared and the localhost names are local."""
        for host in (
            "127.0.0.1",
            "10.0.0.1",
            "192.168.1.1",
            "172.16.0.1",
            "169.254.169.254",
            "100.96.0.9",
            "0.0.0.0",  # noqa: S104 - a host under test
            "localhost.",
            "app.localhost",
            "::ffff:127.0.0.1",
        ):
            with self.subTest(host=host):
                self.assertTrue(urls.is_local(host))

    def test_public(self) -> None:
        """Public addresses and names are not."""
        for host in ("example.org", "93.184.215.14", "1.1.1.1", "localhost.example.org"):
            with self.subTest(host=host):
                self.assertFalse(urls.is_local(host))


class PreapprovedTest(unittest.TestCase):
    """The documentation hosts that get WebFetch's other prompt."""

    def test_hosts_and_prefixes(self) -> None:
        """Whole hosts match any path; prefixed entries match their subtree."""
        self.assertTrue(urls.is_preapproved("https://docs.python.org/3/library/"))
        self.assertTrue(urls.is_preapproved("https://go.dev/doc/effective_go"))
        self.assertTrue(urls.is_preapproved("https://go.dev/doc"))
        self.assertFalse(urls.is_preapproved("https://go.dev/blog/x"))
        self.assertFalse(urls.is_preapproved("https://go.dev/docs"))
        self.assertFalse(urls.is_preapproved("https://example.org/"))

    def test_encoded_separator(self) -> None:
        """An encoded slash or dot never matches a path prefix."""
        self.assertFalse(urls.is_preapproved("https://go.dev/doc%2F..%2Fblog"))

    def test_github(self) -> None:
        """GitHub entries cover only main-branch views outside anthropics."""
        self.assertTrue(urls.is_preapproved("https://github.com/anthropics/anything/pulls"))
        self.assertTrue(urls.is_preapproved("https://github.com/anthropic-experimental/r"))
        self.assertTrue(
            urls.is_preapproved("https://github.com/anthropic-experimental/r/blob/main/a")
        )
        self.assertFalse(urls.is_preapproved("https://github.com/anthropic-experimental/r/issues"))
        self.assertTrue(
            urls.is_preapproved("https://raw.githubusercontent.com/anthropics/r/refs/heads/main/x")
        )
        self.assertFalse(urls.is_preapproved("https://raw.githubusercontent.com/anthropics/r/v1/x"))


class RedirectTest(unittest.TestCase):
    """Which redirects are followed and which are reported."""

    def test_same_host_and_www(self) -> None:
        """The same host, with or without www., is followed."""
        self.assertTrue(urls.redirect_allowed("https://a.example/x", "https://a.example/y"))
        self.assertTrue(urls.redirect_allowed("https://a.example/", "https://www.a.example/"))
        self.assertTrue(urls.redirect_allowed("https://www.a.example/", "https://a.example/z"))

    def test_other_host(self) -> None:
        """Another host or a subdomain is reported."""
        self.assertFalse(urls.redirect_allowed("https://a.example/", "https://b.example/"))
        self.assertFalse(urls.redirect_allowed("https://a.example/", "https://cdn.a.example/"))

    def test_scheme_port_credentials(self) -> None:
        """A scheme or port change and credentials are reported."""
        self.assertFalse(urls.redirect_allowed("https://a.example/", "http://a.example/"))
        self.assertFalse(urls.redirect_allowed("https://a.example/", "https://a.example:8443/"))
        self.assertTrue(urls.redirect_allowed("https://a.example/", "https://a.example:443/"))
        self.assertFalse(urls.redirect_allowed("https://a.example/", "https://u:p@a.example/"))

    def test_leaving_preapproved_path(self) -> None:
        """A redirect out of a preapproved subtree on the same host is reported."""
        self.assertFalse(urls.redirect_allowed("https://go.dev/doc/x", "https://go.dev/blog/y"))
        self.assertTrue(urls.redirect_allowed("https://go.dev/doc/x", "https://go.dev/ref/y"))
