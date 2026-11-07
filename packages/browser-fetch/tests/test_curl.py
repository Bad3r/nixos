# Copyright (c) 2026 Bad3r
"""The curl-impersonate call: argv, the private cookie file, failures."""

import shutil
import tempfile
import unittest
from pathlib import Path

from browser_fetch import cookies as jar
from browser_fetch import curl

from tests.fakes import fake_curl

SECRET = "s3cr3t-session-value"  # noqa: S105 - a stand-in cookie value
COOKIES = [jar.Cookie("session", SECRET, "example.org", "/", 1, secure=True, created=1)]
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
            "https://example.org/",
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

    def test_nameless_cookie_is_sent_bare(self) -> None:
        """A nameless cookie goes out as its value in the Cookie header, never as a file name."""
        self.fake.serve({"https://example.org/": {"status": 200}})
        bare = jar.Cookie("", "token123", "example.org", "/", 1, secure=True, created=1)
        self.run_request(cookies=[bare], identity=None)
        self.assertIn('header = "Cookie: token123"', self.fake.calls()[0]["config"])
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
            "https://example.org/",
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
