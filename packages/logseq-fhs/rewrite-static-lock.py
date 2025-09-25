#!/usr/bin/env python3
import os
import pathlib
import re
import sys
import urllib.parse

if len(sys.argv) != 3:
    print("usage: rewrite-static-lock.py <cache-root> <lockfile>", file=sys.stderr)
    sys.exit(1)

resources_path = sys.argv[1]
lock_path = pathlib.Path(sys.argv[2])
content = lock_path.read_text()

resolved_re = re.compile(r'resolved "(https://registry\.yarnpkg\.com/[^"]+)"')


def sanitize(component: str) -> str:
    return "".join(ch if ch.isalnum() or ch == "." else "_" for ch in component)


def mapped_filename(url: str) -> str:
    if url.startswith("file:"):
        return url.split("/", 1)[-1]
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in ("http", "https"):
        return url
    path_parts = parsed.path.strip("/").split("/")
    if len(path_parts) < 3 or path_parts[-2] != "-":
        return url

    filename = urllib.parse.unquote(path_parts[-1])
    base, _, ext = filename.rpartition('.')
    if not base or not ext:
        return url

    if path_parts[0].startswith("@") and len(path_parts) >= 2:
        scope_raw = path_parts[0][1:]
        pkg_name = path_parts[1]
        prefix = f"_{sanitize(scope_raw)}_{sanitize(pkg_name)}"
    else:
        pkg_name = path_parts[0]
        prefix = sanitize(pkg_name)

    package_basename = path_parts[1] if path_parts[0].startswith("@") and len(path_parts) >= 2 else path_parts[0]
    version_prefix = f"{package_basename}-"
    if base.startswith(version_prefix):
        version_part = base[len(version_prefix) :]
    else:
        parts = base.split('-', 1)
        version_part = parts[1] if len(parts) == 2 else ""

    if not version_part:
        return url

    tail = f"{sanitize(package_basename)}_{sanitize(version_part)}.{ext}"
    return f"{prefix}___{tail}"


def repl(match: re.Match) -> str:
    url = match.group(1)
    return f'resolved "file:{resources_path}/{mapped_filename(url)}"'

lock_path.write_text(resolved_re.sub(repl, content))
