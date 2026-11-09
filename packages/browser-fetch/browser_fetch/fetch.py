# Copyright (c) 2026 Bad3r
"""A WebFetch page fetch: curl first, then the browser when the page needs it."""

from __future__ import annotations

import dataclasses
import http
import os
import secrets
import time
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Literal, Protocol
from urllib.parse import urljoin

from browser_fetch import browser, challenge, convert, curl, urls
from browser_fetch import cookies as jar

if TYPE_CHECKING:
    from collections.abc import Callable
    from pathlib import Path

CURL_SECONDS = 60
BrowserMode = Literal["auto", "never", "always"]
_EXTENSIONS = {
    "application/pdf": "pdf",
    "application/json": "json",
    "text/csv": "csv",
    "text/plain": "txt",
    "text/html": "html",
    "text/markdown": "md",
    "application/zip": "zip",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "xlsx",
    "application/vnd.openxmlformats-officedocument.presentationml.presentation": "pptx",
    "application/msword": "doc",
    "application/vnd.ms-excel": "xls",
    "audio/mpeg": "mp3",
    "audio/wav": "wav",
    "audio/ogg": "ogg",
    "video/mp4": "mp4",
    "video/webm": "webm",
    "image/png": "png",
    "image/jpeg": "jpg",
    "image/gif": "gif",
    "image/webp": "webp",
    "image/svg+xml": "svg",
    "application/epub+zip": "epub",
}


class FetchError(Exception):
    """The page could not be fetched."""


class Renderer(Protocol):
    """The browser fallback, as the fetch uses it."""

    def identity(self, until: float, *, generate: bool = True) -> curl.Identity | None:
        """The headers curl sends so the browser's cookies hold for it; None without one."""
        ...

    def jar(self, until: float) -> list[jar.Cookie]:
        """The cookies of the browser's profile."""
        ...

    def store(self, cookies: jar.Jar, until: float) -> None:
        """Write the fetch's unsaved cookie changes into the browser's profile."""
        ...

    def render(self, url: str, cookies: jar.Jar, until: float, *, keep: bool) -> browser.Rendered:
        """Load url starting from the fetch's cookies and return what the page became."""
        ...


@dataclass
class Page:
    """What WebFetch records of a fetch, before the model reads it."""

    outcome: Literal["ok", "redirect", "http_error"]
    url: str
    status: int
    content_type: str = ""
    bytes: int = 0
    text: str = ""
    via: Literal["curl", "browser"] = "curl"
    reason: str | None = None
    redirect_from: str | None = None
    redirect_to: str | None = None
    retry_after: str | None = None
    saved_path: str | None = None
    saved_bytes: int | None = None
    # Whether a document converter wrote the text, rather than raw bytes.
    converted: bool = False
    # What the fetch did without, for BROWSER_FETCH_DEBUG.
    notes: list[str] = field(default_factory=list[str])
    # What the fetch could not do, such as read or save cookies, always reported.
    warnings: list[str] = field(default_factory=list[str])

    @property
    def status_text(self) -> str:
        """The standard reason phrase of the status."""
        try:
            return http.HTTPStatus(self.status).phrase
        except ValueError:
            return "Unknown Status"


@dataclass(frozen=True)
class Settings:
    """Where the tools are and how the fetch behaves."""

    curl: str
    browser: Renderer
    workdir: Path
    save_dir: Path
    # Whether the profile's cookie jar is read and written at all.
    use_cookies: bool = True
    browser_mode: BrowserMode = "auto"
    deadline: float = 240.0
    clock: Callable[[], float] = time.monotonic


class _Fetch:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.until = settings.clock() + settings.deadline
        self.cookies = jar.Jar()
        self.identity: curl.Identity | None = None
        self.hops = 0
        # Why the browser's identity was left out; printed only for debugging.
        self.notes: list[str] = []
        self.warnings: list[str] = []
        # Why the last write of the jar failed.
        self.unsaved_reason: str | None = None

    def left(self) -> float:
        remaining = self.until - self.settings.clock()
        if remaining <= 0:
            msg = f"the fetch took longer than {self.settings.deadline:.0f} s"
            raise FetchError(msg)
        return remaining

    def load_identity(self) -> None:
        """Take the stored browser fingerprint's headers for curl; render draws a missing one.

        Without them curl sends its Firefox profile's own headers: a curl
        fetch never fails or waits for want of the browser's state.
        """
        try:
            self.identity = self.settings.browser.identity(self.until, generate=False)
        except (browser.BrowserError, OSError) as error:
            self.notes.append(f"curl sends its profile's own headers: {error}")
            return
        if self.identity is None:
            self.notes.append("curl sends its profile's own headers: no fingerprint was drawn yet")

    def load_cookies(self) -> None:
        """Read the profile's jar for curl, unless cookies are off or only the browser runs.

        Camoufox loads the profile itself. A profile another fetch's browser
        holds past the short lock wait is left out with a warning; a database
        that cannot be read is an error.
        """
        if not self.settings.use_cookies or self.settings.browser_mode == "always":
            return
        try:
            self.cookies = jar.Jar.of(self.settings.browser.jar(self.until))
        except browser.BrowserError as error:
            self.warnings.append(f"no cookies were read: {error}")

    def save(self) -> None:
        """Write what the responses did so far to the jar, unless cookies are off.

        It runs as each response arrives, so the writes of overlapping
        fetches land in arrival order, as Gecko applies them. A profile
        another fetch's browser holds past the short lock wait keeps the
        changes pending for the next write; a database that cannot be
        written is an error.
        """
        if not self.settings.use_cookies or not self.cookies.unsaved:
            return
        try:
            self.settings.browser.store(self.cookies, self.until)
        except browser.BrowserError as error:
            self.unsaved_reason = str(error)
        except jar.CookieError as error:
            self.unsaved_reason = str(error)
            raise

    def report_unsaved(self) -> None:
        """Warn of the changes no write took, with their count."""
        if not self.settings.use_cookies or not self.cookies.unsaved:
            return
        reason = self.unsaved_reason or "the fetch ended before they were written"
        self.warnings.append(f"{len(self.cookies.unsaved)} cookie changes were not saved: {reason}")

    def get(self, url: str) -> curl.Response:
        self.hops += 1
        sent = jar.for_request(self.cookies.cookies(), url, jar.now_us() // 1000)
        try:
            response = curl.request(
                url,
                cookies=sent,
                identity=self.identity,
                workdir=self.settings.workdir,
                name=f"hop{self.hops}",
                curl=self.settings.curl,
                timeout=min(CURL_SECONDS, self.left()),
            )
        except curl.TransportError as error:
            # A transfer cut short still delivered its headers' cookies.
            self.receive(url, error.headers)
            raise
        self.receive(url, response.headers)
        return response

    def receive(self, url: str, headers: dict[str, list[str]]) -> None:
        """Apply a response's Set-Cookie headers to the fetch's jar and write them."""
        dates = headers.get("date")
        self.cookies.receive(
            url, headers.get("set-cookie", []), jar.now_us(), dates[-1] if dates else None
        )
        self.save()

    def render(self, url: str) -> browser.Rendered:
        self.left()
        # Camoufox starts with the stored fingerprint, drawn here if none fits its release.
        self.settings.browser.identity(self.until)
        rendered = self.settings.browser.render(
            url, self.cookies, self.until, keep=self.settings.use_cookies
        )
        self.warnings.extend(rendered.warnings)
        return rendered


@dataclass(frozen=True)
class Reply:
    """One response as curl received it, body included."""

    status: int
    headers: dict[str, list[str]]
    body: bytes

    def header(self, name: str) -> str | None:
        """Return the last value of a header, or None."""
        values = self.headers.get(name.lower())
        return values[-1] if values else None


class Client:
    """Single requests as a fetch makes them, for another tool on browser-fetch's jar.

    Each request goes through curl-impersonate with the fingerprint's
    headers and carries the jar's cookies for its URL; what each response
    sets is written back to the jar as it arrives. No redirect is followed and the browser never
    runs, so no fingerprint is drawn.
    """

    def __init__(self, settings: Settings) -> None:
        """Read the fingerprint's headers and the jar; a jar that cannot be read raises."""
        self._run = _Fetch(dataclasses.replace(settings, browser_mode="never"))
        self._run.load_identity()
        self._run.load_cookies()

    @property
    def warnings(self) -> list[str]:
        """What the requests could not do so far, such as read the jar."""
        return self._run.warnings

    def cookies(self, url: str) -> list[jar.Cookie]:
        """The cookies a request for url would carry."""
        return jar.for_request(self._run.cookies.cookies(), url, jar.now_us() // 1000)

    def get(self, url: str) -> Reply:
        """GET the URL once, as a fetch's hop."""
        response = self._run.get(url)
        return Reply(response.status, response.headers, response.body.read_bytes())

    def close(self) -> list[str]:
        """Report the cookie changes no write took, and return every warning."""
        self._run.report_unsaved()
        return self._run.warnings


def _save_binary(body: bytes, content_type: str, save_dir: Path) -> Path:
    save_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    extension = _EXTENSIONS.get(convert.media_type(content_type), "bin")
    name = f"webfetch-{time.time_ns() // 1_000_000}-{secrets.token_hex(3)}.{extension}"
    path = save_dir / name
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as handle:
        handle.write(body)
    return path


def _content(run: _Fetch, page: Page, body: bytes) -> None:
    """Fill the page's text the way WebFetch reads each content type."""
    content_type = page.content_type
    if convert.is_html(content_type):
        page.text = convert.html_to_markdown(convert.decode(body, content_type), run.left())
        return
    if convert.is_binary(content_type):
        saved = _save_binary(body, content_type, run.settings.save_dir)
        page.saved_path, page.saved_bytes = str(saved), len(body)
        if convert.has_converter(content_type):
            page.text = convert.document_to_markdown(body, content_type, run.left())
            page.converted = True
            return
    page.text = convert.decode(body, content_type)


def _successful(status: int) -> bool:
    """Whether WebFetch reads the body: the 2xx class; any other status is an HTTP error."""
    return 200 <= status < 300  # noqa: PLR2004 - the 2xx class


def _via_browser(run: _Fetch, url: str, page_url: str, reason: str) -> Page:
    rendered = run.render(page_url)
    if rendered.blocked is not None:
        return Page(
            "redirect",
            url,
            rendered.blocked.status,
            via="browser",
            reason=reason,
            redirect_from=rendered.blocked.origin,
            redirect_to=rendered.blocked.target,
        )
    if not _successful(rendered.status):
        return Page("http_error", url, rendered.status, via="browser", reason=reason)
    page = Page(
        "ok",
        url,
        rendered.status,
        content_type=rendered.content_type,
        via="browser",
        reason=reason,
    )
    if rendered.html is not None:
        # The DOM is text already; its meta charset no longer applies.
        page.bytes = len(rendered.html.encode("utf-8", "surrogatepass"))
        page.text = convert.html_to_markdown(rendered.html, run.left())
    else:
        page.bytes = len(rendered.body)
        _content(run, page, rendered.body)
    return page


def _retry_after(response: curl.Response) -> str | None:
    value = (response.header("retry-after") or "").strip()
    return value if value.isdigit() and len(value) <= 6 else None  # noqa: PLR2004


def fetch(url: str, settings: Settings) -> Page:
    """Fetch url as WebFetch would, with curl-impersonate and Camoufox's cookie jar.

    What each response did to the jar is written back as it arrives, and a
    failure carries the warnings as its notes.
    """
    target = urls.check_url(url)
    run = _Fetch(settings)
    run.load_identity()
    run.load_cookies()
    try:
        page = _follow(run, url, target)
    except BaseException as error:
        run.report_unsaved()
        for warning in run.warnings:
            error.add_note(warning)
        raise
    run.report_unsaved()
    page.notes = run.notes
    page.warnings = run.warnings
    return page


def _follow(run: _Fetch, url: str, target: str) -> Page:
    """Request target and its same-host redirects with curl, then answer or hand over."""
    if run.settings.browser_mode == "always":
        return _via_browser(run, url, target, "the browser was asked for")
    current = target
    for _ in range(urls.MAX_REDIRECTS + 1):
        response = run.get(current)
        if response.status in urls.REDIRECT_STATUSES:
            location = (response.header("location") or "").strip()
            if not location:
                return Page("http_error", url, response.status)
            following = urljoin(current, location)
            if urls.redirect_allowed(current, following):
                current = following
                continue
            return Page(
                "redirect",
                url,
                response.status,
                redirect_from=current,
                redirect_to=following,
            )
        return _answer(run, url, current, response)
    msg = f"Too many redirects (exceeded {urls.MAX_REDIRECTS})"
    raise FetchError(msg)


def _answer(run: _Fetch, url: str, current: str, response: curl.Response) -> Page:
    body = response.body.read_bytes()
    content_type = response.header("content-type") or ""
    html = convert.decode(body, content_type) if convert.is_html(content_type) else None
    page = Page("ok", url, response.status, content_type=content_type, bytes=len(body))
    ok = _successful(response.status)
    visible = None
    if html is not None and ok:
        page.text = convert.html_to_markdown(html, run.left())
        visible = convert.visible_length(page.text)
    reason = challenge.detect(response.status, response.headers, html, visible)
    if reason is not None and run.settings.browser_mode == "auto":
        try:
            return _via_browser(run, url, current, reason)
        except browser.BrowserError as error:
            # A short page with scripts is still the page curl got.
            if reason != challenge.SHELL:
                raise
            run.warnings.append(
                f"the browser could not render the page, so curl's copy stands: {error}"
            )
    if not ok:
        return Page("http_error", url, response.status, retry_after=_retry_after(response))
    if html is None:
        _content(run, page, body)
    return page
