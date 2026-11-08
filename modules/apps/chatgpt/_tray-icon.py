# Copyright (c) 2026 Bad3r
"""Point ChatGPT's Linux tray at its own image inside app.asar.

On Linux the tray, window, and About icons all load resources/icon-chatgpt.png,
so a tray glyph needs a separate file. The edit pads with spaces to keep the
asar header's file offsets valid, and drops the 16 px downscale so the bar
scales the image instead.
"""

import argparse
import mmap
import re
import sys
from pathlib import Path

LINUX_TRAY = re.compile(
    rb'(?P<head>if\("linux"===process\.platform\)\{let [\w$]+=)'
    rb"`\$\{[\w$]+\([\w$]+\)\}\.png`"
    rb"(?P<load>,(?P<img>[\w$]+)=[\w$]+\.nativeImage\.createFromPath\([^;]*\);"
    rb'if\((?P=img)\.isEmpty\(\)\)throw Error\("Linux tray application icon is unavailable"\);'
    rb"return\{defaultIcon:)"
    rb'(?P=img)\.resize\(\{width:16,height:16,quality:"best"\}\)\}'
)


def main() -> None:
    """Patch the asar archive in place."""
    parser = argparse.ArgumentParser()
    parser.add_argument("asar", type=Path)
    parser.add_argument("icon", help="file name under process.resourcesPath")
    args = parser.parse_args()
    asar: Path = args.asar

    with asar.open("r+b") as f:
        with mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as data:
            matches = list(LINUX_TRAY.finditer(data))
            if len(matches) != 1:
                sys.exit(f"expected 1 Linux tray icon loader in {asar}, got {len(matches)}")
            m = matches[0]
            start = m.start()
            length = m.end() - start
            replacement = m["head"] + f'"{args.icon}"'.encode() + m["load"] + m["img"] + b"}"
        if len(replacement) > length:
            sys.exit(f"replacement longer than original: {replacement!r}")
        f.seek(start)
        f.write(replacement.ljust(length, b" "))


if __name__ == "__main__":
    main()
