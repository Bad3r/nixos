# Copyright (c) 2026 Bad3r
"""Page text for the model: HTML and documents to Markdown, text as it came."""

from __future__ import annotations

import codecs
import functools
import io
import os
import pickle
import re
import select
import signal
import time
import warnings
from html.parser import HTMLParser
from typing import TYPE_CHECKING, NoReturn, override

from markitdown import StreamInfo
from markitdown.converters import (
    DocxConverter,
    EpubConverter,
    HtmlConverter,
    PdfConverter,
    PptxConverter,
    XlsxConverter,
)

from browser_fetch.browser import die_with_parent

if TYPE_CHECKING:
    from collections.abc import Callable

    from markitdown import DocumentConverter

# WebFetch converts at most this many characters of HTML (UTF-16 units).
HTML_LIMIT = 1048576
TRUNCATED = "\n\n[Content truncated due to length...]"
CONVERT_SECONDS = 60
# Removed before conversion, as WebFetch's Turndown removes them (template
# content is never part of the document there).
_DROPPED = frozenset({"noscript", "iframe", "template"})
_META_CHARSET = re.compile(rb"""<meta[^>]+charset\s*=\s*["']?([\w.:-]+)""", re.IGNORECASE)
_SNIFF_BYTES = 2048
# The WHATWG Encoding Standard reads these labels as windows-1252.
_WINDOWS_1252 = frozenset({"latin_1", "iso8859-1", "ascii", "cp1252"})
# Binary documents with a converter; everything else binary is kept as bytes.
_DOCUMENTS: dict[str, tuple[str, Callable[[], DocumentConverter]]] = {
    "application/pdf": (".pdf", PdfConverter),
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": (
        ".docx",
        DocxConverter,
    ),
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": (".xlsx", XlsxConverter),
    "application/vnd.openxmlformats-officedocument.presentationml.presentation": (
        ".pptx",
        PptxConverter,
    ),
    "application/epub+zip": (".epub", EpubConverter),
}


class ConversionError(Exception):
    """A document converter failed or ran out of time."""


def media_type(content_type: str) -> str:
    """Return the lowercase media type without parameters."""
    return content_type.partition(";")[0].strip().lower()


def charset(content_type: str) -> str | None:
    """Return the charset parameter of a Content-Type, if any."""
    for parameter in content_type.split(";")[1:]:
        key, _, value = parameter.partition("=")
        if key.strip().lower() == "charset" and value.strip():
            return value.strip().strip("\"'")
    return None


def is_binary(content_type: str) -> bool:
    """Whether WebFetch treats the content type as binary."""
    kind = media_type(content_type)
    if not kind:
        return False
    return not (
        kind.startswith(("text/", "application/javascript"))
        or kind in {"application/json", "application/xml", "application/x-www-form-urlencoded"}
        or kind.endswith(("+json", "+xml"))
    )


def is_html(content_type: str) -> bool:
    """Whether WebFetch converts the body as HTML."""
    return "text/html" in content_type.lower()


def _known(encoding: str | None) -> str | None:
    if not encoding:
        return None
    try:
        name = codecs.lookup(encoding).name
    except LookupError:
        return None
    return "cp1252" if name in _WINDOWS_1252 else name


def decode(body: bytes, content_type: str) -> str:
    """Decode a body by its declared charset, else a meta charset, else UTF-8."""
    encoding = _known(charset(content_type))
    if encoding is None and is_html(content_type):
        found = _META_CHARSET.search(body[:_SNIFF_BYTES])
        encoding = _known(found.group(1).decode("ascii", "replace")) if found else None
    return body.decode(encoding or "utf-8", errors="replace")


def utf16_length(text: str) -> int:
    """Return the length JavaScript gives the text."""
    return len(text.encode("utf-16-le", "surrogatepass")) // 2


def utf16_slice(text: str, start: int, stop: int | None = None) -> str:
    """Slice text by UTF-16 code units, as a JavaScript string slices."""
    units = text.encode("utf-16-le", "surrogatepass")
    end = None if stop is None else 2 * stop
    return units[2 * start : end].decode("utf-16-le", "surrogatepass")


class _Spans(HTMLParser):
    """Finds the source spans of the elements to drop."""

    def __init__(self, text: str) -> None:
        super().__init__(convert_charrefs=True)
        self.spans: list[tuple[int, int]] = []
        # getpos() counts lines at "\n" alone, unlike str.splitlines().
        self._lines = [0] + [match.end() for match in re.finditer("\n", text)]
        self._text = text
        self._depth = 0
        self._start = 0

    def _offset(self) -> int:
        line, column = self.getpos()
        return self._lines[line - 1] + column

    @override
    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in _DROPPED:
            if self._depth == 0:
                self._start = self._offset()
            self._depth += 1

    @override
    def handle_endtag(self, tag: str) -> None:
        if tag in _DROPPED and self._depth > 0:
            self._depth -= 1
            if self._depth == 0:
                end = self._text.find(">", self._offset())
                self.spans.append((self._start, len(self._text) if end < 0 else end + 1))

    def close_spans(self) -> list[tuple[int, int]]:
        """Return the spans, an unclosed element running to the end."""
        if self._depth > 0:
            self.spans.append((self._start, len(self._text)))
        return self.spans


def strip_dropped(html: str) -> str:
    """Remove noscript, iframe and template elements with their content."""
    parser = _Spans(html)
    parser.feed(html)
    parser.close()
    kept: list[str] = []
    position = 0
    for start, end in parser.close_spans():
        kept.append(html[position:start])
        position = end
    kept.append(html[position:])
    return "".join(kept)


def _markitdown(converter: DocumentConverter, data: bytes, info: StreamInfo) -> str:
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        return converter.convert(io.BytesIO(data), info).markdown


def _read_all(fd: int, deadline: float) -> bytes | None:
    """Read fd to its end, or return None once the deadline passes."""
    chunks: list[bytes] = []
    while True:
        left = deadline - time.monotonic()
        if left <= 0 or not select.select([fd], [], [], left)[0]:
            return None
        chunk = os.read(fd, 1 << 16)
        if not chunk:
            return b"".join(chunks)
        chunks.append(chunk)


def _child(  # pragma: no cover - the child
    parent: int, read_end: int, write_end: int, work: Callable[[], str]
) -> NoReturn:
    """Write work's outcome to the pipe and exit; never return into the parent's code."""
    status = 1
    try:
        die_with_parent()
        os.close(read_end)
        if os.getppid() == parent:
            try:
                outcome: tuple[bool, str] = (True, work())
                status = 0
            except BaseException as error:  # noqa: BLE001 - reported to the parent by type
                outcome = (False, type(error).__name__)
            with os.fdopen(write_end, "wb") as sink:
                sink.write(pickle.dumps(outcome))
    finally:
        os._exit(status)


def in_child[**P](
    seconds: float, what: str, work: Callable[P, str], *args: P.args, **kwargs: P.kwargs
) -> str:
    """Run work in a forked child that is killed at the deadline.

    A converter catches any exception, a timeout's included, so only a
    process boundary bounds it.
    """
    if seconds <= 0:
        msg = f"no time was left to convert {what}"
        raise ConversionError(msg)
    parent = os.getpid()
    read_end, write_end = os.pipe()
    pid = os.fork()
    if pid == 0:  # pragma: no cover - the child
        _child(parent, read_end, write_end, functools.partial(work, *args, **kwargs))
    os.close(write_end)
    data: bytes | None = None
    try:
        data = _read_all(read_end, time.monotonic() + seconds)
    finally:
        os.close(read_end)
        if data is None:
            os.kill(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
    if data is None:
        msg = f"{what} took longer than {seconds:.0f} s to convert"
        raise ConversionError(msg)
    if not data:
        msg = f"{what} could not be converted: the converter died"
        raise ConversionError(msg)
    ok, value = pickle.loads(data)  # noqa: S301 - written by the forked child
    if not ok:
        msg = f"{what} could not be converted: {value}"
        raise ConversionError(msg)
    return value


def _html(html: str) -> str:
    # A lone surrogate (a pair split at HTML_LIMIT, or one in a DOM) becomes
    # "?": encoded as is, it is invalid UTF-8 and the whole page is misdecoded.
    cleaned = strip_dropped(html).encode("utf-8", "replace")
    return _markitdown(
        HtmlConverter(),
        cleaned,
        StreamInfo(mimetype="text/html", charset="utf-8", extension=".html"),
    ).strip()


def html_to_markdown(html: str, seconds: float = CONVERT_SECONDS) -> str:
    """Convert a page as WebFetch does: its first 1 MiB of characters, whole."""
    truncated = utf16_length(html) > HTML_LIMIT
    if truncated:
        html = utf16_slice(html, 0, HTML_LIMIT)
    markdown = in_child(min(seconds, CONVERT_SECONDS), "the page", _html, html)
    return markdown + TRUNCATED if truncated else markdown


def visible_length(markdown: str) -> int:
    """Return how many characters of the Markdown a reader sees."""
    text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", markdown)
    text = re.sub(r"[#*_`>|\\-]", " ", text)
    return len("".join(text.split()))


def has_converter(content_type: str) -> bool:
    """Whether a binary content type has a document converter."""
    return media_type(content_type) in _DOCUMENTS


def _document(body: bytes, kind: str) -> str:
    extension, factory = _DOCUMENTS[kind]
    return _markitdown(factory(), body, StreamInfo(mimetype=kind, extension=extension))


def document_to_markdown(body: bytes, content_type: str, seconds: float = CONVERT_SECONDS) -> str:
    """Convert a PDF, Office or EPUB document; the converters read only body."""
    kind = media_type(content_type)
    return in_child(min(seconds, CONVERT_SECONDS), f"the {kind} document", _document, body, kind)
