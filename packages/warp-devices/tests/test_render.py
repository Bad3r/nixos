# Copyright (c) 2026 Bad3r
"""Table alignment and color selection."""

import io
import re
import unicodedata
import unittest
import unittest.mock

from warp_devices.render import Row, table, use_color

SGR = re.compile(r"\033\[[0-9;]*m")
HEADER = ["NAME", "STATUS", "LAST_SEEN"]
ROWS = [
    Row(["songbird", "connected", "1 min ago"], "connected"),
    Row(["iPhone", "disconnected", None], "disconnected"),
    Row(["tpnix", "offline", "Tue Oct 20, 01:05 (14 days ago)"], "offline"),
]


class Terminal(io.StringIO):
    """A stream that claims to be a terminal."""

    def isatty(self) -> bool:
        """Report a terminal."""
        return True


class TableTest(unittest.TestCase):
    """Padding is computed on plain text, so color never shifts a column."""

    def test_plain_alignment(self) -> None:
        """Columns line up, missing cells print as a dash, lines end without padding."""
        lines = table(HEADER, ROWS, status_column=1, color=False).splitlines()
        self.assertEqual(lines[0], "NAME      STATUS        LAST_SEEN")
        self.assertEqual(lines[2], "iPhone    disconnected  -")
        self.assertTrue(all(line == line.rstrip() for line in lines))

    def test_color_strips_to_plain(self) -> None:
        """Removing the escape codes gives the plain table exactly."""
        colored = table(HEADER, ROWS, status_column=1, color=True)
        self.assertNotEqual(colored, SGR.sub("", colored))
        self.assertEqual(SGR.sub("", colored), table(HEADER, ROWS, status_column=1, color=False))

    def test_status_styles(self) -> None:
        """Connected is bold green, offline red, and rows not connected are dimmed."""
        lines = table(HEADER, ROWS, status_column=1, color=True).splitlines()
        self.assertIn("\033[1;32mconnected", lines[1])
        self.assertIn("\033[1msongbird", lines[1])
        self.assertIn("\033[31moffline", lines[3])
        self.assertIn("\033[2mtpnix", lines[3])
        self.assertIn("\033[2m-", lines[2])

    def test_controls_are_escaped(self) -> None:
        """Terminal controls in API text print as visible escapes, and columns stay aligned."""
        hostile = "evil\x1b]0;pwned\x07\x1b[2J\x9b\x7f"
        rows = [Row([hostile, "connected", "now"], "connected"), *ROWS]
        for color in (False, True):
            with self.subTest(color=color):
                output = table(
                    ["NA\tME", "STATUS", "LAST_SEEN"], rows, status_column=1, color=color
                )
                plain = SGR.sub("", output)
                self.assertNotRegex(plain, r"[\x00-\x09\x0b-\x1f\x7f-\x9f]")
                self.assertIn(r"evil\x1b]0;pwned\x07\x1b[2J\x9b\x7f", plain)
                self.assertTrue(plain.startswith(r"NA\x09ME"))
                starts = {len(line) - len(line.split(maxsplit=1)[1]) for line in plain.splitlines()}
                self.assertEqual(starts, {len(r"evil\x1b]0;pwned\x07\x1b[2J\x9b\x7f") + 2})

    def test_format_characters_are_escaped(self) -> None:
        """Bidi, zero-width, surrogate, separator, and private-use characters print as escapes."""
        hostile = "evil\u202etxt.exe\u200b\u2066\xad\U000e0001\ud800\u2028\u2029\ue000"
        escaped = r"evil\u202etxt.exe\u200b\u2066\xad\U000e0001\ud800\u2028\u2029\ue000"
        rows = [Row([hostile, "connected", "now"], "connected"), *ROWS]
        for color in (False, True):
            with self.subTest(color=color):
                plain = SGR.sub("", table(HEADER, rows, status_column=1, color=color))
                self.assertFalse(
                    any(unicodedata.category(c) in {"Cf", "Cs", "Co", "Zl", "Zp"} for c in plain)
                )
                self.assertIn(escaped, plain)
                plain.encode()
                starts = {len(line) - len(line.split(maxsplit=1)[1]) for line in plain.splitlines()}
                self.assertEqual(starts, {len(escaped) + 2})


class ColorChoiceTest(unittest.TestCase):
    """Explicit flags win; otherwise a terminal without NO_COLOR gets color."""

    def test_matrix(self) -> None:
        """Every combination of flag, terminal, and NO_COLOR."""
        for choice, tty, no_color, expected in (
            (True, False, "1", True),
            (False, True, None, False),
            (None, True, None, True),
            (None, True, "1", False),
            (None, True, "", True),
            (None, False, None, False),
        ):
            env = {} if no_color is None else {"NO_COLOR": no_color}
            stream = Terminal() if tty else io.StringIO()
            with (
                self.subTest(choice=choice, tty=tty, no_color=no_color),
                unittest.mock.patch.dict("os.environ", env, clear=True),
            ):
                self.assertEqual(use_color(choice, stream), expected)
