# Copyright (c) 2026 Bad3r
"""URL checks and the redirect policy."""

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

    def test_local_and_dotless_hosts_are_taken(self) -> None:
        """Loopback, private, link-local and dotless hosts are URLs like any other."""
        for given, wanted in (
            ("http://localhost:8000/", "https://localhost:8000/"),
            ("http://router/status", "https://router/status"),
            ("http://127.0.0.1:3000/", "https://127.0.0.1:3000/"),
            ("http://10.0.0.1/", "https://10.0.0.1/"),
            ("https://192.168.1.10/a", "https://192.168.1.10/a"),
            ("http://169.254.169.254/latest", "https://169.254.169.254/latest"),
            ("http://100.96.0.9/", "https://100.96.0.9/"),
        ):
            with self.subTest(url=given):
                self.assertEqual(urls.check_url(given), wanted)

    def test_ipv6_literals_are_serialized_as_the_url_standard_does(self) -> None:
        """Lowercase hex pieces, embedded IPv4 in hex, the first longest zero run compressed."""
        for given, wanted in (
            ("http://[::1]:8080/", "https://[::1]:8080/"),
            ("http://[::ffff:127.0.0.1]/x", "https://[::ffff:7f00:1]/x"),
            ("https://[2001:DB8::1]/", "https://[2001:db8::1]/"),
            ("http://[fd00:0:0:0:0:0:0:1]/", "https://[fd00::1]/"),
            ("http://[1:0:0:0:2:0:0:0]/", "https://[1::2:0:0:0]/"),
            ("http://[1:0:2:3:4:5:6:7]/", "https://[1:0:2:3:4:5:6:7]/"),
            ("http://[0:0:0:0:0:0:0:0]/", "https://[::]/"),
        ):
            with self.subTest(url=given):
                self.assertEqual(urls.check_url(given), wanted)

    def test_bad_ipv6_literals_are_invalid(self) -> None:
        """A zone ID or a malformed literal is WebFetch's invalid URL, as the URL parser says."""
        for bad in ("http://[fe80::1%25eth0]/", "http://[::g]/", "http://[1:2:3:4:5:6:7:8:9]/"):
            with self.subTest(bad=bad), self.assertRaisesRegex(urls.UrlError, "^Invalid URL$"):
                urls.check_url(bad)

    def test_hosts_are_serialized_as_the_url_standard_does(self) -> None:
        """Unicode names become A-labels, numeric hosts dotted quads, case folds."""
        self.assertEqual(
            urls.check_url("https://Bücher.example/a"), "https://xn--bcher-kva.example/a"
        )
        self.assertEqual(urls.check_url("http://0x7f.1/"), "https://127.0.0.1/")
        self.assertEqual(urls.check_url("https://EXAMPLE.org/"), "https://example.org/")
        with self.assertRaises(urls.UrlError):
            urls.check_url("https://1.2.3.999/")


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

    def test_leaving_documentation_path(self) -> None:
        """A same-host redirect out of a subtree the built-in preapproves is followed."""
        self.assertTrue(urls.redirect_allowed("https://go.dev/doc/x", "https://go.dev/blog/y"))
