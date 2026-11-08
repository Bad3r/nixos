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


class PinTest(unittest.TestCase):
    """Each request's host, resolved once, checked and pinned."""

    def test_private_addresses_are_refused(self) -> None:
        """Loopback, private, shared, link-local, documentation and mapped addresses."""
        for address in (
            "127.0.0.1",
            "10.0.0.1",
            "192.168.1.1",
            "172.16.0.1",
            "169.254.169.254",
            "100.96.0.9",
            "0.0.0.0",  # noqa: S104 - an address under test
            "192.0.2.10",
            "198.51.100.7",
            "203.0.113.5",
            "::1",
            "fd00::1",
            "fe80::1",
            "2001:db8::1",
            "::ffff:127.0.0.1",
            "64:ff9b::a00:1",
        ):
            with (
                self.subTest(address=address),
                self.assertRaisesRegex(urls.PrivateAddressError, "private network"),
            ):
                urls.pin("https://rebind.example/", lambda _h, _p, a=address: [a])

    def test_one_private_answer_refuses_the_host(self) -> None:
        """A name with a public and a private address is refused, not filtered."""
        with self.assertRaises(urls.PrivateAddressError):
            urls.pin("https://mixed.example/", lambda _h, _p: ["93.184.215.14", "10.1.2.3"])

    def test_literal_hosts_are_checked_without_a_lookup(self) -> None:
        """A numeric host is its own address."""

        def never(_host: str, _port: int) -> list[str]:
            raise AssertionError

        with self.assertRaises(urls.PrivateAddressError):
            urls.pin("https://10.1.2.3/", never)
        self.assertEqual(urls.pin("https://93.184.215.14/x", never).addresses, ("93.184.215.14",))

    def test_public_host_is_pinned_as_spelled_for_curl(self) -> None:
        """The URL's host is the lowercase A-label form the pin names, port and path kept."""
        asked: list[tuple[str, int]] = []

        def resolve(host: str, port: int) -> list[str]:
            asked.append((host, port))
            return ["93.184.215.14", "2606:2800:21f:cb07:6820:80da:af6b:8b2c"]

        pinned = urls.pin("https://Example.ORG:8443/a?b#c", resolve)
        self.assertEqual(asked, [("example.org", 8443)])
        self.assertEqual(pinned.url, "https://example.org:8443/a?b#c")
        self.assertEqual((pinned.host, pinned.port), ("example.org", 8443))
        self.assertEqual(len(pinned.addresses), 2)

    def test_unresolved_host(self) -> None:
        """A name with no address is an error of its own."""
        with self.assertRaisesRegex(urls.AddressError, "did not resolve"):
            urls.pin("https://nowhere.example/", lambda _h, _p: [])


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
