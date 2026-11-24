# Copyright (c) 2026 Bad3r
"""Point Antigravity's Linux tray at its own image beside app.asar.

On Linux the tray loads icon.png from app.asar, which is also the window
icon, so a tray glyph needs a separate file. The edit pads with spaces to keep
the asar header's file offsets valid.
"""

import argparse
import mmap
import re
import sys
from pathlib import Path

TRAY_ICON = re.compile(
    rb"const iconFile = \(0, [\w$]+\.isMacOS\)\(\) \? 'trayTemplate\.png' : 'icon\.png';"
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
            matches = list(TRAY_ICON.finditer(data))
            if len(matches) != 1:
                sys.exit(f"expected 1 tray icon selector in {asar}, got {len(matches)}")
            start, end = matches[0].span()
        # tray.js joins the name onto app.asar/dist/.., so ../ leaves the archive.
        replacement = f"const iconFile = '../{args.icon}';".encode()
        if len(replacement) > end - start:
            sys.exit(f"replacement longer than original: {replacement!r}")
        f.seek(start)
        f.write(replacement.ljust(end - start, b" "))


if __name__ == "__main__":
    main()
