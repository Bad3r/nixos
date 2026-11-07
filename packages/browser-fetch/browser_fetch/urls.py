# Copyright (c) 2026 Bad3r
"""URL checks and the redirect policy of Claude Code 2.1.319's WebFetch."""

from __future__ import annotations

import ipaddress
import re
from urllib.parse import SplitResult, urlsplit, urlunsplit

import idna

MAX_URL_LENGTH = 2000
MAX_REDIRECTS = 10
REDIRECT_STATUSES = frozenset({301, 302, 303, 307, 308})
DEFAULT_PORTS = {"http": 80, "https": 443}

# The hosts and path prefixes WebFetch treats as preapproved documentation.
PREAPPROVED = (
    "platform.claude.com",
    "code.claude.com",
    "claude.dev",
    "www.claude.dev",
    "claude.com/docs",
    "modelcontextprotocol.io",
    "github.com/anthropics",
    "github.com/anthropic-experimental",
    "raw.githubusercontent.com/anthropics",
    "raw.githubusercontent.com/anthropic-experimental",
    "agentskills.io",
    "docs.python.org",
    "en.cppreference.com",
    "docs.oracle.com",
    "learn.microsoft.com",
    "developer.mozilla.org",
    "go.dev/doc",
    "go.dev/ref",
    "www.php.net",
    "docs.swift.org",
    "kotlinlang.org",
    "ruby-doc.org",
    "doc.rust-lang.org",
    "www.typescriptlang.org",
    "react.dev",
    "angular.io",
    "vuejs.org",
    "nextjs.org",
    "expressjs.com",
    "nodejs.org",
    "bun.sh",
    "jquery.com",
    "getbootstrap.com",
    "tailwindcss.com",
    "d3js.org",
    "threejs.org",
    "redux.js.org",
    "webpack.js.org",
    "jestjs.io",
    "reactrouter.com",
    "docs.djangoproject.com",
    "flask.palletsprojects.com",
    "fastapi.tiangolo.com",
    "pandas.pydata.org",
    "numpy.org",
    "www.tensorflow.org",
    "pytorch.org",
    "scikit-learn.org",
    "matplotlib.org",
    "requests.readthedocs.io",
    "jupyter.org",
    "laravel.com",
    "symfony.com",
    "wordpress.org/documentation",
    "docs.spring.io",
    "hibernate.org",
    "tomcat.apache.org",
    "gradle.org",
    "maven.apache.org",
    "asp.net",
    "dotnet.microsoft.com",
    "blazor.net",
    "reactnative.dev",
    "docs.flutter.dev",
    "developer.apple.com",
    "developer.android.com",
    "keras.io",
    "spark.apache.org",
    "huggingface.co/docs",
    "www.kaggle.com/docs",
    "www.mongodb.com",
    "redis.io",
    "www.postgresql.org",
    "dev.mysql.com",
    "www.sqlite.org",
    "graphql.org",
    "prisma.io",
    "docs.getdbt.com",
    "docs.aws.amazon.com",
    "cloud.google.com",
    "kubernetes.io",
    "www.docker.com",
    "www.terraform.io",
    "www.ansible.com",
    "vercel.com/docs",
    "docs.stripe.com",
    "docs.netlify.com",
    "devcenter.heroku.com",
    "dev.wix.com/docs",
    "cypress.io",
    "selenium.dev",
    "docs.unity.com",
    "docs.unrealengine.com",
    "git-scm.com",
    "nginx.org",
    "httpd.apache.org",
)
_HOSTS = frozenset(entry for entry in PREAPPROVED if "/" not in entry)
_PREFIXES: dict[str, list[str]] = {}
for _entry in PREAPPROVED:
    if "/" in _entry:
        _host, _, _rest = _entry.partition("/")
        _PREFIXES.setdefault(_host, []).append(f"/{_rest}")
_GITHUB_HOSTS = frozenset({"github.com", "raw.githubusercontent.com"})
_ENCODED_SEPARATOR = re.compile(r"%(25)*(2f|5c|2e)", re.IGNORECASE)
_RAW_MAIN = re.compile(r"^/[^/]+/[^/]+/refs/heads/main/.")
_GITHUB_MAIN = re.compile(r"^/[^/]+/[^/]+(/?|/(tree|blob)/main(/.*)?)$")


class UrlError(Exception):
    """The URL is not one WebFetch fetches."""


def _github_main(host: str, path: str) -> bool:
    if host == "raw.githubusercontent.com":
        return _RAW_MAIN.match(path) is not None
    return _GITHUB_MAIN.match(path) is not None


def preapproved_location(host: str, path: str) -> bool:
    """Whether host and path fall under a preapproved entry."""
    if host in _HOSTS:
        return True
    prefixes = _PREFIXES.get(host)
    if not prefixes or _ENCODED_SEPARATOR.search(path):
        return False
    for prefix in prefixes:
        if path == prefix or path.startswith(f"{prefix}/"):
            return (
                host not in _GITHUB_HOSTS
                or f"{host}{prefix}" == "github.com/anthropics"
                or _github_main(host, path)
            )
    return False


def _path(parts: SplitResult) -> str:
    return parts.path or "/"


def is_preapproved(url: str) -> bool:
    """Whether WebFetch answers this URL with its documentation prompt."""
    try:
        parts = urlsplit(url)
    except ValueError:
        return False
    return preapproved_location(parts.hostname or "", _path(parts))


def _whatwg_ipv4(host: str) -> str | None:
    """Return the dotted address the URL standard reads a numeric host as.

    None when the last label is not a number, so the host is a name; a
    numeric host the standard rejects raises UrlError.
    """
    labels = host.split(".")
    if labels[-1] == "" and len(labels) > 1:
        labels.pop()
    last = labels[-1]
    if not (last.isdigit() or re.fullmatch(r"0[xX][0-9a-fA-F]*", last)):
        return None
    numbers: list[int] = []
    for label in labels:
        try:
            if label[:2].lower() == "0x":
                numbers.append(int(label[2:] or "0", 16))
            elif len(label) > 1 and label.startswith("0"):
                numbers.append(int(label[1:], 8))
            else:
                numbers.append(int(label, 10))
        except ValueError:
            msg = "Invalid URL"
            raise UrlError(msg) from None
    if len(numbers) > 4 or any(n > 255 for n in numbers[:-1]):  # noqa: PLR2004
        msg = "Invalid URL"
        raise UrlError(msg)
    if numbers[-1] >= 256 ** (5 - len(numbers)):
        msg = "Invalid URL"
        raise UrlError(msg)
    value = numbers[-1] + sum(n * 256 ** (3 - i) for i, n in enumerate(numbers[:-1]))
    return str(ipaddress.IPv4Address(value))


def _ascii_host(host: str) -> str:
    """Return the host as the URL standard serializes it: A-labels, numeric hosts dotted."""
    try:
        host = host if host.isascii() else idna.encode(host, uts46=True).decode("ascii")
    except idna.IDNAError:
        msg = "Invalid URL"
        raise UrlError(msg) from None
    return _whatwg_ipv4(host) or host.lower()


def is_local(host: str) -> bool:
    """Whether the host names this machine or a non-public network.

    Loopback, private, link-local, shared and reserved addresses, and the
    localhost names, which take no cookies and no browser.
    """
    name = host.lower().removesuffix(".")
    if name == "localhost" or name.endswith(".localhost"):
        return True
    try:
        address = ipaddress.ip_address(name.strip("[]"))
    except ValueError:
        return False
    if isinstance(address, ipaddress.IPv6Address) and address.ipv4_mapped is not None:
        address = address.ipv4_mapped
    return not address.is_global


def check_url(url: str) -> str:
    """Return the URL to request, upgraded to https; raise UrlError otherwise.

    The host is written as the URL standard serializes it, so a Unicode name
    becomes its A-labels and a numeric host its dotted address. An IPv6
    literal is refused as dotless, as WebFetch's hostname check refuses it.
    """
    if len(url) > MAX_URL_LENGTH:
        msg = "Invalid URL"
        raise UrlError(msg)
    try:
        parts = urlsplit(url)
        port = parts.port
    except ValueError:
        msg = "Invalid URL"
        raise UrlError(msg) from None
    host = parts.hostname or ""
    if parts.scheme not in DEFAULT_PORTS or not host:
        msg = "Invalid URL"
        raise UrlError(msg)
    if parts.username is not None or parts.password is not None:
        msg = "Invalid URL"
        raise UrlError(msg)
    if "." not in host or ":" in host:
        msg = (
            "WebFetch cannot fetch localhost or other hostnames without a dot. "
            "To reach a local server, use Bash with curl instead."
        )
        raise UrlError(msg)
    host = _ascii_host(host)
    dropped = {None, 80} if parts.scheme == "http" else {None}
    netloc = host if port in dropped else f"{host}:{port}"
    return urlunsplit(parts._replace(scheme="https", netloc=netloc))


def _port(parts: SplitResult) -> int | None:
    port = parts.port
    return None if port == DEFAULT_PORTS.get(parts.scheme) else port


def _strip_www(host: str) -> str:
    return host.removeprefix("www.")


def redirect_allowed(origin: str, target: str) -> bool:
    """Whether WebFetch follows a redirect from origin to target itself.

    Only a redirect to the same host, give or take a leading www., on the same
    scheme and port and without credentials is followed; the rest are reported.
    """
    try:
        source, dest = urlsplit(origin), urlsplit(target)
        if dest.scheme != source.scheme or _port(dest) != _port(source):
            return False
    except ValueError:
        return False
    source_host = source.hostname or ""
    bare = _strip_www(source_host)
    hosts = dict.fromkeys([source_host, bare, f"www.{bare}"])
    if any(preapproved_location(h, _path(source)) for h in hosts) and not any(
        preapproved_location(h, _path(dest)) for h in hosts
    ):
        return False
    if dest.username is not None or dest.password is not None:
        return False
    return _strip_www(dest.hostname or "") == bare
