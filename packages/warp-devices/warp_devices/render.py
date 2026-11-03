# Copyright (c) 2026 Bad3r
"""Aligned, optionally colored tables."""

import os
import re
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
CONTROL = re.compile(r"[\x00-\x1f\x7f-\x9f]")


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


def printable(text: str) -> str:
    r"""Replace C0, DEL, and C1 controls with `\x1b`-style escapes, keeping API text inert."""
    return CONTROL.sub(lambda match: f"\\x{ord(match.group()):02x}", text)


def _sgr(text: str, code: str | None, *, color: bool) -> str:
    if not color or not code:
        return text
    return f"\033[{code}m{text}\033[0m"


def table(header: Sequence[str], rows: Sequence[Row], *, status_column: int, color: bool) -> str:
    """Escape and pad on plain text, then wrap each padded cell in its style.

    A row whose status is not connected is dimmed except for its status cell,
    which takes the status color; missing values print as a dim dash.
    """
    titles = [printable(title) for title in header]
    plain = [[printable(cell or MISSING) for cell in row.cells] for row in rows]
    widths = [len(title) for title in titles]
    for cells in plain:
        for index, cell in enumerate(cells):
            widths[index] = max(widths[index], len(cell))
    last = len(titles) - 1

    def pad(index: int, cell: str) -> str:
        return cell if index == last else cell.ljust(widths[index] + GUTTER)

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
