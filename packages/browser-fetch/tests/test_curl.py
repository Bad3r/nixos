# Copyright (c) 2026 Bad3r
"""The curl-impersonate call: argv, the private cookie file, failures."""

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from browser_fetch import cookies as jar
from browser_fetch import curl, tools

from tests.fakes import fake_curl

SECRET = "s3cr3t-session-value"  # noqa: S105 - a stand-in cookie value
COOKIES = [jar.Cookie("session", SECRET, "example.org", "/", 1, secure=True, created=1)]
URL = "https://example.org/"
IDENTITY = curl.Identity(
    "Mozilla/5.0 (X11; Linux x86_64; rv:158.0) Gecko/20100101 Firefox/158.0", "en-US,en;q=0.9"
)


class RequestTest(unittest.TestCase):
    """One request."""

    def setUp(self) -> None:
        """Install the fake curl and a work directory."""
        self.fake, self.holder = fake_curl()
        self.work = Path(tempfile.mkdtemp(prefix="browser-fetch-test-"))

    def tearDown(self) -> None:
        """Remove both."""
        self.holder.cleanup()
        shutil.rmtree(self.work)

    def run_request(
        self, cookies: list[jar.Cookie] | None = None, identity: curl.Identity | None = IDENTITY
    ) -> curl.Response:
        """Request the test URL with the secret cookie."""
        return curl.request(
            URL,
            cookies=COOKIES if cookies is None else cookies,
            identity=identity,
            workdir=self.work,
            name="hop1",
            curl=self.fake.path,
            timeout=5,
        )

    def test_cookie_travels_in_a_private_file(self) -> None:
        """The cookie is in a 0600 config file, never in argv, and the file is gone after."""
        self.fake.serve({"https://example.org/": {"status": 200, "body": "hi"}})
        response = self.run_request()
        (call,) = self.fake.calls()
        self.assertNotIn(SECRET, " ".join(call["argv"]))
        self.assertIn(f'header = "Cookie: session={SECRET}"\n', call["config"])
        self.assertEqual(call["mode"], 0o600)
        self.assertFalse((self.work / "hop1.conf").exists())
        self.assertEqual(response.status, 200)
        self.assertEqual(response.body.read_bytes(), b"hi")

    def test_profile_is_used_unmodified(self) -> None:
        """Only the User-Agent, Accept-Language and Cookie lines override the profile."""
        self.fake.serve({"https://example.org/": {"status": 200}})
        self.run_request()
        call = self.fake.calls()[0]
        self.assertEqual(
            call["config"].splitlines(),
            [
                f'header = "User-Agent: {IDENTITY.user_agent}"',
                f'header = "Accept-Language: {IDENTITY.accept_language}"',
                f'header = "Cookie: session={SECRET}"',
            ],
        )
        argv = call["argv"]
        self.assertEqual(argv[argv.index("--impersonate") + 1], "firefox155")
        self.assertFalse({"-H", "--header", "--http2-stream-weight"} & set(argv))

    def test_no_identity_keeps_the_profile_headers(self) -> None:
        """Without a fingerprint and cookies nothing is overridden."""
        self.fake.serve({"https://example.org/": {"status": 200}})
        self.run_request(cookies=[], identity=None)
        self.assertEqual(self.fake.calls()[0]["config"], "")

    def test_valueless_cookie_goes_in_the_header(self) -> None:
        """A cookie with no value goes out as "name=" in the Cookie header, not curl's option.

        Gecko stores a Set-Cookie token without "=" as the name
        (network.cookie.valueless_cookie) and ComposeCookieString writes
        name "=" value.
        """
        self.fake.serve({"https://example.org/": {"status": 200}})
        flag = jar.Cookie("token123", "", "example.org", "/", 1, secure=True, created=1)
        self.run_request(cookies=[flag], identity=None)
        self.assertIn('header = "Cookie: token123="', self.fake.calls()[0]["config"])
        self.assertNotIn("cookie =", self.fake.calls()[0]["config"])

    def test_impersonation_and_limits(self) -> None:
        """Https only, size cap and no redirects."""
        self.fake.serve({"https://example.org/": {"status": 200}})
        self.run_request()
        argv = self.fake.calls()[0]["argv"]
        self.assertEqual(argv[0], "--disable")
        self.assertEqual(argv[argv.index("--proto") + 1], "=https")
        self.assertEqual(argv[argv.index("--max-filesize") + 1], str(curl.MAX_BYTES))
        self.assertEqual(argv[argv.index("--connect-timeout") + 1], "5")
        self.assertEqual(argv[argv.index("--max-time") + 1], "5")
        self.assertNotIn("--location", argv)

    def test_quotes_are_escaped(self) -> None:
        """A quoted cookie value stays one config string."""
        self.fake.serve({"https://example.org/": {"status": 200}})
        quoted = [jar.Cookie("q", '"a\\b"', "example.org", "/", 1, secure=True, created=1)]
        curl.request(
            URL,
            cookies=quoted,
            identity=None,
            workdir=self.work,
            name="h",
            curl=self.fake.path,
            timeout=5,
        )
        self.assertIn('header = "Cookie: q=\\"a\\\\b\\""\n', self.fake.calls()[0]["config"])

    def test_failure_names_the_cause(self) -> None:
        """A known curl exit code becomes its reason, and the config file is removed."""
        self.fake.serve({"https://example.org/": {"status": 0, "exit": 28}})
        with self.assertRaisesRegex(curl.TransportError, "timed out"):
            self.run_request()
        self.assertFalse((self.work / "hop1.conf").exists())

    def test_proxy_refusal_names_the_proxy(self) -> None:
        """A proxy that answers CONNECT with 407 is named, not taken for a refused connection.

        curl exits 7 ("CONNECT tunnel failed, response 407") and writes the
        proxy's status in %{http_connect}; its code 7 alone reads as a
        connection failure.
        """
        self.fake.serve({"https://example.org/": {"status": 0, "connect": 407, "exit": 7}})
        with self.assertRaisesRegex(curl.TransportError, "proxy refused its credentials.*407"):
            self.run_request()
        self.fake.serve({"https://example.org/": {"status": 0, "connect": 403, "exit": 7}})
        with self.assertRaisesRegex(curl.TransportError, "proxy refused the tunnel with HTTP 403"):
            self.run_request()
        self.fake.serve({"https://example.org/": {"status": 0, "exit": 7}})
        with self.assertRaisesRegex(curl.TransportError, "connection was refused or failed"):
            self.run_request()

    def test_failed_transfer_keeps_the_headers_it_got(self) -> None:
        """Curl writes the status and headers out when the transfer fails after them.

        A body over --max-filesize (63) or a timeout (28) comes after the
        headers. With no response (000), or one from an address other than
        the checked one, there are none to keep.
        """
        cookies = ["sid=; Max-Age=0", "new=1; Max-Age=60"]
        for code, reason in ((63, "larger than"), (28, "timed out")):
            with self.subTest(code=code):
                self.fake.serve(
                    {
                        "https://example.org/": {
                            "status": 200,
                            "exit": code,
                            "headers": {"Set-Cookie": cookies},
                        }
                    }
                )
                with self.assertRaisesRegex(curl.TransportError, reason) as caught:
                    self.run_request()
                self.assertEqual(caught.exception.headers["set-cookie"], cookies)
        self.fake.serve({"https://example.org/": {"status": 0, "exit": 7}})
        with self.assertRaises(curl.TransportError) as caught:
            self.run_request()
        self.assertEqual(caught.exception.headers, {})

    def test_failure_text_never_carries_the_cookie(self) -> None:
        """Curl's own error text is passed on with cookie values masked."""
        self.fake.serve(
            {
                "https://example.org/": {
                    "status": 0,
                    "exit": 99,
                    "stderr": f"bad cookie session={SECRET}\n",
                }
            }
        )
        with self.assertRaises(curl.TransportError) as caught:
            self.run_request()
        self.assertNotIn(SECRET, str(caught.exception))
        self.assertIn("[redacted]", str(caught.exception))

    def test_headers(self) -> None:
        """Headers come back by lowercase name."""
        self.fake.serve({"https://example.org/": {"status": 301, "headers": {"Location": "/x"}}})
        self.assertEqual(self.run_request().header("location"), "/x")

    def test_curl_resolves_and_connects_as_it_would_alone(self) -> None:
        """No address is pinned or checked: a local, private or dotless host goes as given."""
        for url in (
            "https://localhost:8443/",
            "https://router/",
            "https://127.0.0.1:3000/a",
            "https://10.0.0.1/",
            "https://[::1]:8080/",
        ):
            with self.subTest(url=url):
                self.fake.serve({url: {"status": 200, "body": "local"}})
                response = curl.request(
                    url,
                    cookies=[],
                    identity=None,
                    workdir=self.work,
                    name="h",
                    curl=self.fake.path,
                    timeout=5,
                )
                argv = self.fake.calls()[-1]["argv"]
                self.assertNotIn("--resolve", argv)
                self.assertNotIn("--connect-to", argv)
                self.assertEqual(argv[-1], url)
                self.assertEqual(response.status, 200)
                self.assertEqual(response.body.read_text(), "local")


PROXY = "http://proxy.example:3128"
# (host, no_proxy, whether curl goes direct), from curl 8.23's lib/proxy.c
# (proxy_check_noproxy, match_host, match_ip) and CURLOPT_NOPROXY(3).
NO_PROXY_CASES = (
    # CURLOPT_NOPROXY(3): "ample.com" matches ample.com and www.ample.com, not
    # www.example.com or ample.com.org.
    ("ample.com", "ample.com", True),
    ("www.ample.com", "ample.com", True),
    ("www.example.com", "ample.com", False),
    ("ample.com.org", "ample.com", False),
    # match_host, case C: nonexample.com does not match example.com.
    ("notexample.com", "example.com", False),
    # match_host ignores an entry's leading and trailing dot, and
    # proxy_check_noproxy the host's trailing dot.
    ("example.com", ".example.com", True),
    ("www.example.com", ".example.com", True),
    ("example.com", "example.com.", True),
    ("example.com.", "example.com", True),
    # The comparison ignores ASCII case (curl_strnequal).
    ("example.com", "EXAMPLE.Com", True),
    # A lone "*" matches every host; in a list it is a name like any other.
    ("example.com", "*", True),
    ("example.com", "other.example,*", False),
    # Blanks around entries and runs of commas are skipped, so an empty entry
    # matches nothing; an entry followed by a blank and no comma ends the list.
    ("example.com", "other.example,", False),
    ("example.com", ",, other.example ,\texample.com", True),
    ("example.com", "other.example example.com", False),
    # A numeric host matches addresses and /bits ranges, never names
    # (match_ip); no bits, or 0, is the address itself (cidr4_match).
    ("192.0.2.7", "192.0.2.0/24", True),
    ("192.0.2.7", "192.0.3.0/24", False),
    ("192.0.2.7", "192.0.2.7", True),
    ("192.0.2.7", "192.0.2.0", False),
    ("192.0.2.7", "192.0.2.0/0", False),
    ("192.0.2.7", "192.0.2.0/33", False),
    ("192.0.2.7", "2.7", False),
    ("2001:db8::7", "2001:db8::/32", True),
    ("2001:db8::7", "2001:db9::/32", False),
    ("2001:db8::7", "2001:db8::7", True),
)


class ProxyChoiceTest(unittest.TestCase):
    """The proxy curl uses for an https URL to a host (curl 8.23's lib/proxy.c)."""

    def test_variables_in_curls_order(self) -> None:
        """https_proxy, HTTPS_PROXY, all_proxy, then ALL_PROXY; an empty one counts as unset."""
        a, b, c, d = (f"http://{name}.example:3128" for name in "abcd")
        for environ, server in (
            ({"ALL_PROXY": d}, d),
            ({"all_proxy": c, "ALL_PROXY": d}, c),
            ({"HTTPS_PROXY": b, "all_proxy": c, "ALL_PROXY": d}, b),
            ({"https_proxy": a, "HTTPS_PROXY": b, "all_proxy": c}, a),
            ({"https_proxy": "", "HTTPS_PROXY": "", "ALL_PROXY": d}, d),
            ({"http_proxy": a, "HTTP_PROXY": b}, None),
        ):
            with self.subTest(environ=environ):
                self.assertEqual(curl.proxy("example.com", environ), server)

    def test_no_proxy_entries(self) -> None:
        """no_proxy names hosts curl reaches directly, by curl's own matching."""
        for host, no_proxy, direct in NO_PROXY_CASES:
            with self.subTest(host=host, no_proxy=no_proxy):
                chosen = curl.proxy(host, {"ALL_PROXY": PROXY, "no_proxy": no_proxy})
                self.assertEqual(chosen, None if direct else PROXY)

    def test_no_proxy_variables(self) -> None:
        """no_proxy, else NO_PROXY; an empty one counts as unset, so it exempts nothing."""
        for listed, server in (
            ({"NO_PROXY": "example.com"}, None),
            ({"no_proxy": "", "NO_PROXY": "example.com"}, None),
            ({"no_proxy": "other.example", "NO_PROXY": "example.com"}, PROXY),
            ({"no_proxy": ""}, PROXY),
        ):
            with self.subTest(listed=listed):
                self.assertEqual(curl.proxy("example.com", {"ALL_PROXY": PROXY, **listed}), server)


@unittest.skipIf(
    tools.CURL.startswith("@"), "the source tree's tools are not store paths; run the package"
)
class CurlAgreesTest(unittest.TestCase):
    """curl-impersonate itself makes each choice, as its verbose log reports it."""

    def uses_proxy(self, host: str, environ: dict[str, str]) -> bool:
        """Whether curl took a proxy for https://host/; nothing leaves loopback."""
        named = f"[{host}]" if ":" in host else host
        ran = subprocess.run(
            [
                tools.CURL,
                "--disable",
                "--silent",
                "--verbose",
                "--max-time",
                "5",
                "--connect-to",
                "::127.0.0.1:1",
                f"https://{named}/",
            ],
            capture_output=True,
            text=True,
            env={"PATH": "/var/empty", "ALL_PROXY": "http://127.0.0.1:1", **environ},
            timeout=30,
            check=False,
        )
        return "Uses proxy env variable ALL_PROXY" in ran.stderr

    def test_no_proxy_entries(self) -> None:
        """Every no_proxy case is curl's own decision."""
        for host, no_proxy, direct in NO_PROXY_CASES:
            with self.subTest(host=host, no_proxy=no_proxy):
                environ = {"no_proxy": no_proxy}
                self.assertEqual(self.uses_proxy(host, environ), not direct)
                chosen = curl.proxy(host, {"ALL_PROXY": PROXY, **environ})
                self.assertEqual(chosen is not None, not direct)
