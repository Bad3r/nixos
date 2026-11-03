# Copyright (c) 2026 Bad3r
"""Aligned, optionally colored tables."""

import os
import unicodedata
from dataclasses import dataclass
from typing import TYPE_CHECKING, TextIO

if TYPE_CHECKING:
    from collections.abc import Sequence

MISSING = "-"
GUTTER = 2
BOLD = "1"
DIM = "2"
STATUS_STYLES = {
    "connected": "1;32",
    "disconnected": "33",
    "offline": "31",
    "unknown": DIM,
}
ESCAPED_CATEGORIES = frozenset({"Cc", "Cf", "Cs", "Co", "Zl", "Zp"})
LATIN1_MAX = 0xFF
BMP_MAX = 0xFFFF
WIDE = frozenset({"W", "F"})


@dataclass(frozen=True)
class Row:
    """Cells of one table row and the status that colors it."""

    cells: Sequence[str | None]
    status: str | None = None


def use_color(choice: bool | None, stream: TextIO) -> bool:  # noqa: FBT001 - tri-state flag
    """Honor an explicit choice, else color a terminal unless NO_COLOR is set."""
    if choice is not None:
        return choice
    return stream.isatty() and not os.environ.get("NO_COLOR")


def _escape(char: str) -> str:
    code = ord(char)
    if code <= LATIN1_MAX:
        return f"\\x{code:02x}"
    if code <= BMP_MAX:
        return f"\\u{code:04x}"
    return f"\\U{code:08x}"


def printable(text: str) -> str:
    r"""Escape control, format, surrogate, private-use, and line or paragraph separators.

    The `\x1b`, `\u202e`, or `\U000e0001` forms keep API text from driving the terminal,
    reordering or breaking a line, hiding characters, or failing to encode.
    """
    return "".join(
        _escape(char) if unicodedata.category(char) in ESCAPED_CATEGORIES else char for char in text
    )


def width(text: str) -> int:
    """Return the terminal columns of escaped text."""
    return sum(
        0 if unicodedata.combining(char) else 2 if unicodedata.east_asian_width(char) in WIDE else 1
        for char in text
    )


def _sgr(text: str, code: str | None, *, color: bool) -> str:
    if not color or not code:
        return text
    return f"\033[{code}m{text}\033[0m"


def table(header: Sequence[str], rows: Sequence[Row], *, status_column: int, color: bool) -> str:
    """Escape and pad on plain text by display width, then wrap each padded cell in its style.

    A row whose status is not connected is dimmed except for its status cell,
    which takes the status color; missing values print as a dim dash.
    """
    titles = [printable(title) for title in header]
    plain = [[printable(cell or MISSING) for cell in row.cells] for row in rows]
    widths = [width(title) for title in titles]
    for cells in plain:
        for index, cell in enumerate(cells):
            widths[index] = max(widths[index], width(cell))
    last = len(titles) - 1

    def pad(index: int, cell: str) -> str:
        return cell if index == last else cell + " " * (widths[index] + GUTTER - width(cell))

    lines = ["".join(_sgr(pad(i, title), BOLD, color=color) for i, title in enumerate(titles))]
    for row, cells in zip(rows, plain, strict=True):
        styled: list[str] = []
        for index, cell in enumerate(cells):
            if index == status_column:
                code = STATUS_STYLES.get(row.status or "")
            elif cell == MISSING or row.status != "connected":
                code = DIM
            elif index == 0:
                code = BOLD
            else:
                code = None
            styled.append(_sgr(pad(index, cell), code, color=color))
        lines.append("".join(styled))
    return "\n".join(lines) + "\n"
