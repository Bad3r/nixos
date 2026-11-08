# Copyright (c) 2026 Bad3r
"""HTML pages as numbered lines with link markers."""

import unittest

from kagi_search import fetch, render

LIMIT = 40


def html(url: str, body: str) -> fetch.Page:
    """Return an HTML page as the fetcher hands it over."""
    return fetch.Page(url, "text/html", body, redirected=False)


class RenderTest(unittest.TestCase):
    """HTML to numbered lines."""

    def test_links_and_skipped_markup(self) -> None:
        """Navigation, scripts, hidden and non-http links stay out of the link table."""
        page = html(
            "https://a.org/dir/page",
            '<nav><a href="/n">nav</a></nav><p><a href="#top">Top</a> '
            '<a href="javascript:alert(1)">js</a> <a href="mailto:x@a.org">mail</a> '
            '<a href="../up">Up</a> <a href="https://b.org/">B \u3010x\u2020y\u3011</a> '
            '<a href="#top">Top</a> <a href="http://[::1">bad</a></p>'
            '<div hidden><a href="/h">hidden</a></div>'
            '<base href="https://c.org/"><p><a href="rel">Rel</a></p>',
        )
        rendered = render.render(page)
        self.assertEqual(
            rendered.lines,
            [
                (
                    "\u30100\u2020Top\u3011 js mail \u30101\u2020Up\u3011 "
                    "\u30102\u2020B x y\u2020b.org\u3011 \u30100\u2020Top\u3011 bad"
                ),
                "",
                "\u30103\u2020Rel\u2020c.org\u3011",
            ],
        )
        self.assertEqual(
            rendered.links,
            [
                "https://a.org/dir/page#top",
                "https://a.org/up",
                "https://b.org/",
                "https://c.org/rel",
            ],
        )

    def test_structure(self) -> None:
        """Headings, lists, tables, and preformatted text keep their shape."""
        page = html(
            "https://a.org/",
            "<h1>T</h1><ul><li>a<ol><li>b</li><li>c</li></ol></li></ul>"
            "<table><tr><th>k</th><td>v</td></tr></table><pre>x\n  y</pre>",
        )
        self.assertEqual(
            render.render(page).lines,
            ["# T", "", "  * a", "    1. b", "    2. c", "", "k | v", "", "x", "  y"],
        )

    def test_long_lines_split_outside_link_markers(self) -> None:
        """Segments stay within the limit, keep markers whole, and rejoin to the line."""
        marker = "\u30107\u2020a link with spaces\u2020b.org\u3011"
        line = " ".join(["word"] * 3 + [marker] + ["filler"] * 2)
        segments = render.split_line(line, LIMIT)
        self.assertEqual(segments, ["word word word", f"{marker} filler", "filler"])
        self.assertTrue(all(len(segment) <= LIMIT for segment in segments))
        self.assertEqual(render.split_line("x" * 45, LIMIT), ["x" * LIMIT, "x" * 5])
        self.assertEqual(render.split_line(""), [""])

    def test_render_splits_long_lines(self) -> None:
        """A paragraph longer than SEGMENT_CHARS becomes several numbered lines."""
        text = " ".join(["word"] * 1000)
        lines = render.render(html("https://a.org/", f"<p>{text}</p>")).lines
        self.assertGreater(len(lines), 1)
        self.assertTrue(all(len(line) <= render.SEGMENT_CHARS for line in lines))
        self.assertEqual(" ".join(lines), text)
