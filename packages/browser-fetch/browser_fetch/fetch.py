# Copyright (c) 2026 Bad3r
"""A WebFetch page fetch: curl first, then the browser when the page needs it."""

from __future__ import annotations

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

    def identity(self, until: float) -> curl.Identity | None:
        """The headers curl sends so the browser's cookies hold for it."""
        ...

    def jar(self, until: float) -> list[jar.Cookie]:
        """The cookies the browser holds of its own, none it was lent."""
        ...

    def render(
        self,
        url: str,
        librewolf: list[jar.Cookie],
        received: list[jar.Cookie],
        until: float,
    ) -> browser.Rendered:
        """Load url with the cookies merged in and return what the page became."""
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
    use_cookies: bool = True
    browser_mode: BrowserMode = "auto"
    deadline: float = 240.0
    clock: Callable[[], float] = time.monotonic
    # The resolver each hop's host is checked and pinned with.
    resolve: Callable[[str, int], list[str]] = urls.lookup


class _Fetch:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.until = settings.clock() + settings.deadline
        self.librewolf: list[jar.Cookie] = []
        self.camoufox: list[jar.Cookie] = []
        self.received: list[jar.Cookie] = []
        self.identity: curl.Identity | None = None
        self.hops = 0
        # Why the browser's state was left out; printed only for debugging.
        self.notes: list[str] = []

    def left(self) -> float:
        remaining = self.until - self.settings.clock()
        if remaining <= 0:
            msg = f"the fetch took longer than {self.settings.deadline:.0f} s"
            raise FetchError(msg)
        return remaining

    def load_cookies(self) -> None:
        """Read the browser's own jar, and LibreWolf's unless cookies are off.

        The browser's jar is optional: when its state cannot be read the
        fetch goes on without it.
        """
        try:
            self.camoufox = self.settings.browser.jar(self.until)
        except (browser.BrowserError, jar.CookieError, OSError) as error:
            self.notes.append(f"the browser's own cookies were left out: {error}")
        if not self.settings.use_cookies:
            return
        profile = jar.default_profile(jar.librewolf_root())
        self.librewolf = jar.read(jar.snapshot(profile, self.settings.workdir))

    def get(self, url: str) -> curl.Response:
        self.hops += 1
        now = jar.now_ms()
        stored = jar.merge(jar.live(self.camoufox, now), jar.live(self.librewolf, now))
        sent = jar.for_request(jar.merge(self.received, stored), url, now)
        response = curl.request(
            urls.pin(url, self.settings.resolve),
            cookies=sent,
            identity=self.identity,
            workdir=self.settings.workdir,
            name=f"hop{self.hops}",
            curl=self.settings.curl,
            timeout=min(CURL_SECONDS, self.left()),
        )
        self.received = jar.apply(self.received, url, response.headers.get("set-cookie", []), now)
        return response

    def render(self, url: str) -> browser.Rendered:
        self.left()
        return self.settings.browser.render(url, self.librewolf, self.received, self.until)


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
    """Fetch url as WebFetch would, with curl-impersonate and the browsers' cookies.

    Every hop's host is resolved and checked before anything is sent: one on
    this machine or a private network is refused.
    """
    target = urls.check_url(url)
    urls.pin(target, settings.resolve)
    run = _Fetch(settings)
    run.identity = settings.browser.identity(run.until)
    run.load_cookies()
    page = _follow(run, url, target)
    page.notes = run.notes
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
    ok = 200 <= response.status < 300  # noqa: PLR2004 - the 2xx class
    visible = None
    if html is not None and ok:
        page.text = convert.html_to_markdown(html, run.left())
        visible = convert.visible_length(page.text)
    reason = challenge.detect(response.status, response.headers, html, visible)
    if reason is not None and run.settings.browser_mode == "auto":
        try:
            return _via_browser(run, url, current, reason)
        except browser.BrowserError:
            # A short page with scripts is still the page curl got.
            if reason != challenge.SHELL:
                raise
    if not ok:
        return Page("http_error", url, response.status, retry_after=_retry_after(response))
    if html is None:
        _content(run, page, body)
    return page
