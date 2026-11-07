# Copyright (c) 2026 Bad3r
"""Decoding, HTML conversion, document conversion and UTF-16 windows."""

import contextlib
import io
import time
import unittest
import zipfile

from browser_fetch import convert


class TypeTest(unittest.TestCase):
    """How WebFetch sorts content types."""

    def test_binary(self) -> None:
        """Text, JSON, XML and JavaScript are text; the rest is binary."""
        for text in (
            "text/plain",
            "text/html; charset=utf-8",
            "application/json",
            "application/ld+json",
            "application/rss+xml",
            "application/xml",
            "application/javascript",
            "application/x-www-form-urlencoded",
            "",
        ):
            with self.subTest(text=text):
                self.assertFalse(convert.is_binary(text))
        for binary in (
            "application/pdf",
            "image/png",
            "application/octet-stream",
            "application/zip",
        ):
            with self.subTest(binary=binary):
                self.assertTrue(convert.is_binary(binary))

    def test_charset(self) -> None:
        """The charset parameter is read case-insensitively and unquoted."""
        self.assertEqual(convert.charset('text/html; Charset="ISO-8859-1"'), "ISO-8859-1")
        self.assertIsNone(convert.charset("text/html"))


class DecodeTest(unittest.TestCase):
    """Bodies to text."""

    def test_declared_charset(self) -> None:
        """The header's charset decodes the body."""
        self.assertEqual(
            convert.decode("café".encode("latin-1"), "text/plain; charset=latin-1"), "café"
        )

    def test_meta_charset(self) -> None:
        """An HTML page without a header charset is read by its meta tag."""
        body = '<meta charset="windows-1252"><p>café</p>'.encode("cp1252")
        self.assertIn("café", convert.decode(body, "text/html"))

    def test_latin1_label_is_windows_1252(self) -> None:
        """As the Encoding Standard reads it, iso-8859-1 is windows-1252: 0x85 is an ellipsis."""
        self.assertEqual(convert.decode(b"a\x85b", "text/html; charset=iso-8859-1"), "a\u2026b")

    def test_unknown_charset_falls_back_to_utf8(self) -> None:
        """An unknown charset name decodes as UTF-8 with replacements."""
        self.assertEqual(convert.decode("é".encode(), "text/plain; charset=bogus"), "é")


class HtmlTest(unittest.TestCase):
    """HTML to Markdown."""

    def test_dropped_elements(self) -> None:
        """noscript, iframe, template, script and style never reach the text, nested or not."""
        html = (
            "<p>keep</p><noscript>Enable JavaScript</noscript><iframe>frame</iframe>"
            "<template><p>a<template>b</template>c</p></template><script>x()</script>"
            "<style>p{}</style><p>tail</p>"
        )
        markdown = convert.html_to_markdown(html)
        self.assertEqual(markdown.split(), ["keep", "tail"])

    def test_line_breaks_other_than_newline(self) -> None:
        """Only a newline starts a line for the parser, whatever str.splitlines() splits on."""
        for separator in ("\x0c", "\x85", "\u2028", "\r", "\x0b", "\x1c"):
            with self.subTest(separator=repr(separator)):
                html = (
                    f"<p>Intro{separator}text</p>\n<p>FIRST PARAGRAPH</p>\n"
                    "<iframe>frame</iframe>\n<p>second</p>"
                )
                stripped = convert.strip_dropped(html)
                self.assertIn("FIRST PARAGRAPH", stripped)
                self.assertNotIn("frame</iframe>", stripped)
                self.assertIn("<p>second</p>", stripped)

    def test_unclosed_dropped_element(self) -> None:
        """An unclosed noscript drops the rest of the page."""
        self.assertEqual(convert.strip_dropped("<p>a</p><noscript><p>b"), "<p>a</p>")

    def test_markdown(self) -> None:
        """Headings, links and lists survive."""
        markdown = convert.html_to_markdown(
            '<h1>Title</h1><ul><li><a href="https://x.example/">Link</a></li></ul>'
        )
        self.assertIn("# Title", markdown)
        self.assertIn("[Link](https://x.example/)", markdown)

    def test_truncation(self) -> None:
        """HTML past 1 MiB characters is cut there and marked."""
        html = "<p>" + "a" * (convert.HTML_LIMIT + 10) + "</p>"
        markdown = convert.html_to_markdown(html)
        self.assertTrue(markdown.endswith(convert.TRUNCATED))
        self.assertLessEqual(len(markdown), convert.HTML_LIMIT + len(convert.TRUNCATED))

    def test_visible_length(self) -> None:
        """Link targets and Markdown punctuation do not count as text."""
        self.assertEqual(convert.visible_length("# A [b](https://long.example/path) *c*"), 3)


class Utf16Test(unittest.TestCase):
    """Offsets count UTF-16 code units, as the plugin's JavaScript does."""

    def test_length(self) -> None:
        """An astral character is two units."""
        self.assertEqual(convert.utf16_length("a😀b"), 4)

    def test_slice_splits_pairs(self) -> None:
        """A slice may split a pair, leaving a lone surrogate at its edge."""
        self.assertEqual(convert.utf16_slice("a😀b", 2), "\ude00b")
        self.assertEqual(convert.utf16_slice("a😀b", 0, 2), "a\ud83d")
        self.assertEqual(convert.utf16_slice("a😀b", 1, 3), "😀")


class DocumentTest(unittest.TestCase):
    """Binary documents through markitdown's converters, from bytes only."""

    def test_epub(self) -> None:
        """An EPUB's chapters become Markdown, metadata first."""
        data = io.BytesIO()
        with zipfile.ZipFile(data, "w") as book:
            book.writestr(
                "META-INF/container.xml",
                '<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles>'
                "</container>",
            )
            book.writestr(
                "OEBPS/content.opf",
                '<package xmlns:dc="http://purl.org/dc/elements/1.1/"><metadata>'
                "<dc:title>Fixture</dc:title></metadata>"
                '<manifest><item id="c1" href="c1.xhtml"/></manifest>'
                '<spine><itemref idref="c1"/></spine></package>',
            )
            book.writestr(
                "OEBPS/c1.xhtml", "<html><body><h1>Chapter</h1><p>Body.</p></body></html>"
            )
        markdown = convert.document_to_markdown(data.getvalue(), "application/epub+zip")
        self.assertIn("**Title:** Fixture", markdown)
        self.assertIn("# Chapter", markdown)

    def test_deadline_survives_a_converter_that_catches_everything(self) -> None:
        """A converter swallowing every exception is still stopped at the deadline."""

        def stubborn() -> str:
            while True:
                with contextlib.suppress(Exception):  # what markitdown's converters do
                    time.sleep(30)

        started = time.monotonic()
        with self.assertRaisesRegex(convert.ConversionError, "longer than"):
            convert.in_child(0.5, "the test", stubborn)
        self.assertLess(time.monotonic() - started, 5)

    def test_html_conversion_is_bounded(self) -> None:
        """HTML conversion has the same bound; none left is an error at once."""
        with self.assertRaisesRegex(convert.ConversionError, "no time"):
            convert.html_to_markdown("<p>x</p>", 0)

    def test_broken_document(self) -> None:
        """Bytes that are no PDF fail as a conversion error."""
        with self.assertRaises(convert.ConversionError):
            convert.document_to_markdown(b"not a pdf", "application/pdf")

    def test_only_documents_have_converters(self) -> None:
        """Images, archives and audio keep their bytes."""
        self.assertTrue(convert.has_converter("application/pdf"))
        for kind in ("application/zip", "image/png", "audio/mpeg"):
            with self.subTest(kind=kind):
                self.assertFalse(convert.has_converter(kind))
