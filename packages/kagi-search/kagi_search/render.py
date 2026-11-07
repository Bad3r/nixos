# Copyright (c) 2026 Bad3r
"""Fetched pages as numbered lines whose links carry numbered markers."""

from __future__ import annotations

import re
import urllib.parse
from dataclasses import dataclass
from html.parser import HTMLParser
from typing import TYPE_CHECKING, override

from kagi_search.fetch import HTML_TYPES
from kagi_search.page import VOID

if TYPE_CHECKING:
    from collections.abc import Callable

    from kagi_search.fetch import Page

LINK_START = "\u3010"
LINK_END = "\u3011"
LINK_SEPARATOR = "\u2020"
SEGMENT_CHARS = 1000
SKIPPED_TAGS = frozenset(
    {
        "button",
        "canvas",
        "footer",
        "iframe",
        "nav",
        "noscript",
        "object",
        "script",
        "select",
        "style",
        "svg",
        "template",
        "textarea",
    }
)
OPTIONAL_END_TAGS = frozenset(
    {"dd", "dt", "li", "option", "p", "rp", "rt", "tbody", "td", "tfoot", "th", "thead", "tr"}
)
BLOCK_TAGS = frozenset(
    {
        "address",
        "article",
        "aside",
        "dd",
        "details",
        "dialog",
        "div",
        "dl",
        "dt",
        "fieldset",
        "figcaption",
        "figure",
        "form",
        "header",
        "hgroup",
        "hr",
        "main",
        "section",
        "summary",
        "table",
        "tr",
    }
)
HEADINGS = {f"h{level}": level for level in range(1, 7)}


@dataclass(frozen=True)
class Rendered:
    """A page as numbered lines and the link table its markers number."""

    title: str
    lines: list[str]
    links: list[str]


def _clean(text: str) -> str:
    text = text.translate({ord(LINK_START): " ", ord(LINK_END): " ", ord(LINK_SEPARATOR): " "})
    return " ".join(text.split())


@dataclass
class _Link:
    url: str | None
    parts: list[str]


@dataclass
class _List:
    ordered: bool
    items: int = 0


class _Renderer(HTMLParser):
    """HTML to numbered-line text with 【id†text†domain】 link markers."""

    def __init__(self, url: str) -> None:
        super().__init__(convert_charrefs=True)
        self.base = url
        self.host = urllib.parse.urlsplit(url).hostname
        self.lines: list[str] = []
        self.parts: list[str] = []
        self.marker: str | None = None
        self.heading: str | None = None
        self.lists: list[_List] = []
        self.quote = 0
        self.pre = 0
        self.skip_tag: str | None = None
        self.skip_depth = 0
        self.in_title = False
        self.title: list[str] = []
        self.link: _Link | None = None
        self.links: list[str] = []
        self.link_ids: dict[str, int] = {}

    def _prefix(self) -> str:
        prefix = "> " * self.quote
        if self.marker is not None:
            prefix += self.marker
            self.marker = None
        elif self.lists:
            prefix += "  " * (len(self.lists) + 1)
        return prefix + (self.heading or "")

    def _flush(self) -> None:
        line = "".join(self.parts)
        self.parts = []
        line = line.rstrip() if self.pre else line.strip()
        if line or self.pre:
            self.lines.append(self._prefix() + line if line else "")

    def _blank(self) -> None:
        if self.lines and self.lines[-1]:
            self.lines.append("")

    def _block(self, *, blank: bool = False) -> None:
        if self.link is not None:
            self.link.parts.append(" ")
            return
        self._flush()
        if blank:
            self._blank()

    def _text(self, text: str) -> None:
        if not self.pre:
            text = re.sub(r"\s+", " ", text)
            if not self.parts or self.parts[-1].endswith(" "):
                text = text.lstrip()
        if text:
            self.parts.append(text)

    def _link_url(self, href: str | None) -> str | None:
        if not href:
            return None
        try:
            url = urllib.parse.urljoin(self.base, href.strip())
            scheme = urllib.parse.urlsplit(url).scheme.lower()
        except ValueError:
            return None
        return url if scheme in {"http", "https"} else None

    def _close_link(self) -> None:
        link = self.link
        if link is None:
            return
        self.link = None
        raw = "".join(link.parts)
        text = _clean(raw)
        if not text:
            return
        if raw[:1].isspace():
            self._text(" ")
        if link.url is None:
            self._text(text)
        else:
            number = self.link_ids.get(link.url)
            if number is None:
                number = self.link_ids[link.url] = len(self.links)
                self.links.append(link.url)
            host = urllib.parse.urlsplit(link.url).hostname
            domain = "" if host == self.host else f"{LINK_SEPARATOR}{host}"
            self.parts.append(f"{LINK_START}{number}{LINK_SEPARATOR}{text}{domain}{LINK_END}")
        if raw[-1:].isspace():
            self._text(" ")

    def _skips(self, tag: str, values: dict[str, str | None]) -> bool:
        if tag in SKIPPED_TAGS:
            return True
        if tag in OPTIONAL_END_TAGS:
            return False
        return "hidden" in values or values.get("aria-hidden") == "true"

    def _open_list_item(self) -> None:
        self._block()
        if not self.lists:
            self.lists.append(_List(ordered=False))
        current = self.lists[-1]
        current.items += 1
        bullet = f"{current.items}. " if current.ordered else "* "
        self.marker = "  " * len(self.lists) + bullet

    def _open_link(self, values: dict[str, str | None]) -> None:
        self._close_link()
        self.link = _Link(self._link_url(values.get("href")), [])

    def _open_list(self, *, ordered: bool) -> None:
        self._block()
        self.lists.append(_List(ordered=ordered))

    def _close_list(self) -> None:
        self._block()
        if self.lists:
            self.lists.pop()
        if not self.lists:
            self._blank()

    def _open_quote(self) -> None:
        self._block()
        self.quote += 1

    def _close_quote(self) -> None:
        self._block()
        self.quote = max(self.quote - 1, 0)

    def _open_pre(self) -> None:
        self._block()
        self.pre += 1

    def _close_pre(self) -> None:
        self._block(blank=True)
        self.pre = max(self.pre - 1, 0)

    def _code(self) -> None:
        if not self.pre:
            self._inline("`")

    def _cell(self) -> None:
        if self.parts:
            self._inline(" | ")

    def _starts(self, tag: str, values: dict[str, str | None]) -> None:
        actions: dict[str, Callable[[], None]] = {
            "title": lambda: setattr(self, "in_title", True),
            "a": lambda: self._open_link(values),
            "li": self._open_list_item,
            "ul": lambda: self._open_list(ordered=False),
            "ol": lambda: self._open_list(ordered=True),
            "blockquote": self._open_quote,
            "pre": self._open_pre,
            "code": self._code,
            "td": self._cell,
            "th": self._cell,
        }
        action = actions.get(tag)
        if action is not None:
            action()
        elif tag in HEADINGS:
            self._block()
            self.heading = "#" * HEADINGS[tag] + " "
        elif tag in BLOCK_TAGS or tag == "p":
            self._block()

    def _ends(self, tag: str) -> None:
        actions: dict[str, Callable[[], None]] = {
            "title": lambda: setattr(self, "in_title", False),
            "a": self._close_link,
            "p": lambda: self._block(blank=True),
            "table": lambda: self._block(blank=True),
            "ul": self._close_list,
            "ol": self._close_list,
            "blockquote": self._close_quote,
            "pre": self._close_pre,
            "code": self._code,
        }
        action = actions.get(tag)
        if action is not None:
            action()
        elif tag in HEADINGS:
            self._block(blank=True)
            self.heading = None
        elif tag in BLOCK_TAGS or tag == "li":
            self._block()

    @override
    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if self.skip_tag is not None:
            if tag == self.skip_tag:
                self.skip_depth += 1
            return
        values = dict(attrs)
        if tag in VOID:
            self._void(tag, values)
        elif tag != "title" and self._skips(tag, values):
            self.skip_tag, self.skip_depth = tag, 1
        else:
            self._starts(tag, values)

    def _void(self, tag: str, values: dict[str, str | None]) -> None:
        if tag == "br":
            self._block()
        elif tag == "hr":
            self._block(blank=True)
        elif tag == "base":
            url = self._link_url(values.get("href"))
            if url is not None:
                self.base = url

    def _inline(self, text: str) -> None:
        if self.link is not None:
            self.link.parts.append(text)
        else:
            self.parts.append(text)

    @override
    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.handle_starttag(tag, attrs)
        if tag not in VOID:
            self.handle_endtag(tag)

    @override
    def handle_endtag(self, tag: str) -> None:
        if self.skip_tag is None:
            self._ends(tag)
        elif tag == self.skip_tag:
            self.skip_depth -= 1
            if self.skip_depth == 0:
                self.skip_tag = None

    @override
    def handle_data(self, data: str) -> None:
        if self.skip_tag is not None:
            return
        if self.in_title:
            self.title.append(data)
        elif self.link is not None:
            self.link.parts.append(data)
        elif self.pre:
            first, *rest = data.split("\n")
            self._text(first)
            for segment in rest:
                self._flush()
                self._text(segment)
        else:
            self._text(data)

    def result(self) -> Rendered:
        """Return the rendered page."""
        self._close_link()
        self.pre = 0
        self._flush()
        lines = self.lines
        while lines and not lines[-1]:
            lines.pop()
        while lines and not lines[0]:
            lines.pop(0)
        return Rendered(_clean("".join(self.title)), lines, self.links)


def _break_at(line: str, limit: int) -> int:
    """Return where to cut the line: the last space within limit outside a link marker."""
    depth = 0
    cut = 0
    for index, char in enumerate(line[: limit + 1]):
        if char == LINK_START:
            depth += 1
        elif char == LINK_END:
            depth = max(depth - 1, 0)
        elif char.isspace() and depth == 0 and index:
            cut = index
    return cut or limit


def split_line(line: str, limit: int = SEGMENT_CHARS) -> list[str]:
    """Return the line cut into segments of at most limit characters, at spaces when possible."""
    segments: list[str] = []
    while len(line) > limit:
        cut = _break_at(line, limit)
        head, line = line[:cut].rstrip(), line[cut:].lstrip()
        if head:
            segments.append(head)
    if line or not segments:
        segments.append(line)
    return segments


def render(page: Page) -> Rendered:
    """Return the page as numbered-line text, long lines split into numbered segments."""
    body = page.body or ""
    if page.content_type in HTML_TYPES:
        renderer = _Renderer(page.url)
        renderer.feed(body)
        renderer.close()
        rendered = renderer.result()
    else:
        rendered = Rendered("", [line.rstrip() for line in body.splitlines()], [])
    lines = [segment for line in rendered.lines for segment in split_line(line)]
    return Rendered(rendered.title, lines, rendered.links)
