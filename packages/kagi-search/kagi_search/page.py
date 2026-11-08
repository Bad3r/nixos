# Copyright (c) 2026 Bad3r
"""Hits from Kagi's no-JavaScript results page."""

from __future__ import annotations

import re
from dataclasses import dataclass
from html.parser import HTMLParser

VOID = frozenset(
    {
        "area",
        "base",
        "br",
        "col",
        "embed",
        "hr",
        "img",
        "input",
        "link",
        "meta",
        "source",
        "track",
        "wbr",
    }
)
RAW_TEXT = frozenset({"script", "style", "template"})
CONTAINERS = frozenset({"search-result", "__srgi"})
LAST_BLANK_CODE_POINT = 0x20


@dataclass(frozen=True)
class Hit:
    """One search result."""

    title: str
    url: str
    snippet: str


class UnrecognizedPageError(Exception):
    """A page that is neither results nor Kagi's no-results answer."""

    def __init__(self, title: str) -> None:
        """Name the page's title and the likely markup change."""
        super().__init__(
            f"Kagi's page held no search results kagi-search recognizes "
            f"(title: {title or 'none'}); its markup may have changed"
        )


@dataclass
class _Frame:
    depth: int
    href: str | None = None
    title: list[str] | None = None
    title_depth: int | None = None
    group_title_depth: int | None = None
    desc: list[str] | None = None
    desc_depth: int | None = None
    skip_depth: int | None = None


def _text(parts: list[str]) -> str:
    return re.sub(r"\s+", " ", "".join(parts)).strip()


def _skip_summarize(frame: _Frame, tag: str, classes: set[str], depth: int) -> None:
    """Start skipping the summarize link inside a description."""
    if frame.skip_depth is None and tag == "a" and "summarize-link" in classes:
        frame.skip_depth = depth


def _open_title(frame: _Frame, href: str | None, classes: set[str], depth: int) -> None:
    """Start collecting the title link of a plain or grouped result."""
    if "__sri_title_link" in classes or frame.group_title_depth is not None:
        frame.href = href
        frame.title = []
        frame.title_depth = depth


def _open_section(frame: _Frame, classes: set[str], depth: int) -> None:
    """Mark where a group title or a description starts."""
    if "__srgi-title" in classes and frame.group_title_depth is None:
        frame.group_title_depth = depth
    if "__sri-desc" in classes and frame.desc is None:
        frame.desc = []
        frame.desc_depth = depth


class _Parser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.stack: list[str] = []
        self.frame: _Frame | None = None
        self.hits: list[Hit] = []
        self.no_results = False
        self.page_title: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        classes = set((values.get("class") or "").split())
        if "no-results-options" in classes:
            self.no_results = True
        if tag in VOID:
            return
        self.stack.append(tag)
        depth = len(self.stack)
        frame = self.frame
        if frame is None:
            if classes & CONTAINERS:
                self.frame = _Frame(depth=depth)
        elif frame.desc_depth is not None:
            _skip_summarize(frame, tag, classes, depth)
        elif frame.title is None and tag == "a":
            _open_title(frame, values.get("href"), classes, depth)
        else:
            _open_section(frame, classes, depth)

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag not in VOID:
            self.handle_starttag(tag, attrs)
            self.handle_endtag(tag)

    def handle_endtag(self, tag: str) -> None:
        if tag not in self.stack:
            return
        while self.stack:
            depth = len(self.stack)
            closed = self.stack.pop()
            self._close(depth)
            if closed == tag:
                return

    def _close(self, depth: int) -> None:
        frame = self.frame
        if frame is None:
            return
        if frame.skip_depth == depth:
            frame.skip_depth = None
        if frame.title_depth == depth:
            frame.title_depth = None
        if frame.group_title_depth == depth:
            frame.group_title_depth = None
        if frame.desc_depth == depth:
            frame.desc_depth = None
        if frame.depth == depth:
            self.frame = None
            if frame.href and frame.title is not None:
                self.hits.append(Hit(_text(frame.title), frame.href, _text(frame.desc or [])))

    def handle_data(self, data: str) -> None:
        if self.stack and self.stack[-1] in RAW_TEXT:
            return
        if self.stack and self.stack[-1] == "title":
            self.page_title.append(data)
        frame = self.frame
        if frame is None:
            return
        if frame.title_depth is not None and frame.title is not None:
            frame.title.append(data)
        if frame.desc_depth is not None and frame.skip_depth is None and frame.desc is not None:
            frame.desc.append(data)


def parse_page(html: str) -> list[Hit]:
    """Return the page's hits in page order, each URL once.

    Raises UnrecognizedPageError for a page that yields no hits and is not
    Kagi's no-results answer, result containers or not.
    """
    parser = _Parser()
    parser.feed(html)
    parser.close()
    if not parser.hits and not parser.no_results:
        raise UnrecognizedPageError(_text(parser.page_title))
    hits: list[Hit] = []
    seen: set[str] = set()
    for hit in parser.hits:
        if hit.title and is_plain_url(hit.url) and hit.url not in seen:
            seen.add(hit.url)
            hits.append(hit)
    return hits


_HOST = re.compile(
    r"^https?://([a-z0-9-]+(?:\.[a-z0-9-]+)*\.?)(?::\d{1,5})?(?:[/?#]|$)", re.IGNORECASE
)


def host_of(url: str) -> str | None:
    r"""Return the URL's host, or None unless every URL parser reads the same one.

    A backslash, userinfo, or any character outside a plain DNS name is refused, so
    a URL such as https://evil.example\@good.example/ cannot pass for good.example.
    """
    if "\\" in url or any(ord(char) <= LAST_BLANK_CODE_POINT for char in url):
        return None
    match = _HOST.match(url)
    return match.group(1).rstrip(".").lower() if match else None


def is_plain_url(url: str) -> bool:
    """Tell whether the URL has an unambiguous host."""
    return host_of(url) is not None


def _domain(value: str) -> str:
    value = re.sub(r"^[a-z][a-z0-9+.-]*://", "", value.strip().lower())
    return re.sub(r"[/?#:].*$", "", value).lstrip("*.").rstrip(".")


def _domains(values: list[str] | None) -> list[str]:
    return [d for d in map(_domain, values or []) if d]


def _matches(host: str, domain: str) -> bool:
    return host == domain or host.endswith(f".{domain}")


def filter_hits(
    hits: list[Hit], allowed: list[str] | None = None, blocked: list[str] | None = None
) -> list[Hit]:
    """Drop hits with an ambiguous host, a blocked domain, or a domain outside allowed."""
    allow = _domains(allowed)
    block = _domains(blocked)
    kept: list[Hit] = []
    for hit in hits:
        host = host_of(hit.url)
        if host is None or any(_matches(host, d) for d in block):
            continue
        if allow and not any(_matches(host, d) for d in allow):
            continue
        kept.append(hit)
    return kept


_OPERAND = re.compile(r"[a-z0-9-]+(?:\.[a-z0-9-]+)*")


def _operands(values: list[str] | None) -> list[str]:
    # Only plain host names reach Kagi's query syntax; filter_hits still applies the rest.
    return list(dict.fromkeys(d for d in _domains(values) if _OPERAND.fullmatch(d)))


def kagi_query(
    query: str, allowed: list[str] | None = None, blocked: list[str] | None = None
) -> str:
    """Narrow the query with site: for allowed domains and -site: for blocked ones."""
    allow = _operands(allowed)
    parts = [query]
    if len(allow) == 1:
        parts.append(f"site:{allow[0]}")
    elif allow:
        parts.append("(" + " OR ".join(f"site:{d}" for d in allow) + ")")
    parts += [f"-site:{d}" for d in _operands(blocked)]
    return " ".join(parts)
