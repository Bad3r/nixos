# Copyright (c) 2026 Bad3r
"""Table alignment and color selection."""

import io
import re
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
