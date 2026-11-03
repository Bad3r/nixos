# Copyright (c) 2026 Bad3r
"""Build an OpenType icon font from square SVG icons.

Usage:
    python3 _octicons-font.py OUTPUT FAMILY ICON_DIR CODEPOINT=NAME...

Each NAME resolves to ICON_DIR/NAME-16.svg and is mapped to CODEPOINT; a NAME
repeated under several codepoints shares one glyph.
"""

import re
import sys
from pathlib import Path
from typing import TYPE_CHECKING

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.svgLib.path import SVGPath

if TYPE_CHECKING:
    from fontTools.misc.psCharStrings import T2CharString

UNITS_PER_EM = 1000
# Line metrics of the bar font (MonoLisaText), so icons never grow the bar.
ASCENT = 1040
DESCENT = 340
# Icon square, centered on the cap height.
ICON_SIZE = 1000
ICON_BOTTOM = -150


def icon_charstring(svg: Path) -> tuple[T2CharString, tuple[int, int]]:
    """Return the icon's charstring and its advance width and left side bearing."""
    view_box = re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', svg.read_text(encoding="utf-8"))
    if view_box is None:
        message = f"{svg}: missing viewBox"
        raise ValueError(message)
    scale = ICON_SIZE / float(view_box.group(2))
    advance = round(float(view_box.group(1)) * scale)
    outline = RecordingPen()
    SVGPath(str(svg), transform=(scale, 0, 0, -scale, 0, ICON_BOTTOM + ICON_SIZE)).draw(outline)
    bounds = BoundsPen(None)
    outline.replay(bounds)
    pen = T2CharStringPen(advance, None)
    outline.replay(pen)
    x_min = bounds.bounds[0] if bounds.bounds else 0
    return pen.getCharString(), (advance, round(x_min))


def main() -> None:
    """Write the font described by the command line."""
    output, family, icon_dir, *mappings = sys.argv[1:]
    glyph_order = [".notdef"]
    charstrings = {".notdef": T2CharStringPen(ICON_SIZE, None).getCharString()}
    metrics = {".notdef": (ICON_SIZE, 0)}
    cmap: dict[int, str] = {}
    for mapping in mappings:
        codepoint, name = mapping.split("=", 1)
        if name not in charstrings:
            charstrings[name], metrics[name] = icon_charstring(Path(icon_dir) / f"{name}-16.svg")
            glyph_order.append(name)
        cmap[int(codepoint)] = name

    ps_name = family.replace(" ", "")
    builder = FontBuilder(UNITS_PER_EM, isTTF=False)
    builder.setupGlyphOrder(glyph_order)
    builder.setupCharacterMap(cmap)
    builder.setupCFF(ps_name, {"FullName": family}, charstrings, {})
    builder.setupHorizontalMetrics(metrics)
    builder.setupHorizontalHeader(ascent=ASCENT, descent=-DESCENT)
    builder.setupNameTable({"familyName": family, "styleName": "Regular", "psName": ps_name})
    builder.setupOS2(
        version=4,
        sTypoAscender=ASCENT,
        sTypoDescender=-DESCENT,
        sTypoLineGap=0,
        usWinAscent=ASCENT,
        usWinDescent=DESCENT,
        fsSelection=0x40 | 0x80,
    )
    builder.setupPost()
    Path(output).parent.mkdir(parents=True, exist_ok=True)
    builder.save(output)


if __name__ == "__main__":
    main()
