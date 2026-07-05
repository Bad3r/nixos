#!/usr/bin/env python3

"""Update Gecko Violentmonkey userscript pins."""

import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any, cast
from urllib.parse import urlencode


def _flake_root(start: Path) -> Path:
    """Walk up from ``start`` until ``flake.nix`` is found."""
    for parent in [start, *start.parents]:
        if (parent / "flake.nix").is_file():
            return parent
    msg = f"Could not find flake.nix above {start}"
    raise RuntimeError(msg)


FLAKE_ROOT = _flake_root(Path(__file__).resolve().parent)
sys.path.insert(0, str(FLAKE_ROOT / "scripts"))

from updater import (  # noqa: E402
    calculate_url_hash,
    fetch_json,
    fetch_text,
    load_hashes,
    save_hashes,
)

PINS_FILE = FLAKE_ROOT / "modules" / "browsers" / "_gecko-userscripts.json"
META_BLOCK_RE = re.compile(
    r"(?:^|\n).*?//[\x20\t]*==UserScript==(?P<body>[\s\S]*?\n).*?//[\x20\t]*==/UserScript=="
)
META_ITEM_RE = re.compile(r"(?:^|\n).*?//[\x20\t]*@(?P<key>\S+)(?P<value>.*)")

LIST_KEYS = {
    "include",
    "exclude",
    "match",
    "excludeMatch",
    "require",
    "grant",
}


def camel_case_meta_key(key: str) -> str:
    """Convert userscript metadata keys to Violentmonkey's storage keys."""
    result = key.replace("-", "_")
    while "_" in result:
        left, right = result.split("_", 1)
        result = left + right[:1].upper() + right[1:]
    return result


def parse_userscript_meta(code: str) -> dict[str, Any]:
    """Parse a userscript metadata block into Violentmonkey's JSON shape."""
    match = META_BLOCK_RE.search(code)
    if match is None:
        msg = "Could not find a ==UserScript== metadata block"
        raise RuntimeError(msg)

    meta: dict[str, Any] = {
        "include": [],
        "exclude": [],
        "match": [],
        "excludeMatch": [],
        "require": [],
        "grant": [],
        "resources": {},
    }

    for item in META_ITEM_RE.finditer(match.group("body")):
        key = camel_case_meta_key(item.group("key"))
        value = item.group("value").strip()

        if key == "resource":
            name, _, url = value.partition(" ")
            if name and url:
                cast("dict[str, str]", meta["resources"])[name] = url
            continue

        if key in LIST_KEYS:
            cast("list[str]", meta[key]).append(value)
            continue

        if key in meta:
            current = meta[key]
            if isinstance(current, list):
                cast("list[str]", current).append(value)
            continue

        meta[key] = value

    name = meta.get("name")
    if not isinstance(name, str) or not name:
        msg = "Userscript metadata is missing @name"
        raise RuntimeError(msg)

    return meta


def github_path_commit(repo: str, branch: str, path: str) -> dict[str, Any]:
    """Fetch the latest commit on ``branch`` that changed ``path``."""
    query = urlencode({"sha": branch, "path": path, "per_page": "1"})
    url = f"https://api.github.com/repos/{repo}/commits?{query}"
    commits = cast("list[dict[str, Any]]", fetch_json(url))
    if not commits:
        msg = f"No commits found for {repo}:{branch}:{path}"
        raise RuntimeError(msg)
    return commits[0]


def raw_github_url(repo: str, rev: str, path: str) -> str:
    """Build an immutable raw.githubusercontent.com URL."""
    return f"https://raw.githubusercontent.com/{repo}/{rev}/{path}"


def date_to_epoch_ms(value: str) -> int:
    """Convert a GitHub ISO timestamp to epoch milliseconds."""
    return int(datetime.fromisoformat(value).timestamp() * 1000)


def save_script_source(path: Path, code: str) -> bool:
    """Write a vendored userscript source file when its content changed."""
    if path.exists() and path.read_text() == code:
        return False

    path.write_text(code)
    return True


def update_pin(name: str, pin: dict[str, Any]) -> tuple[dict[str, Any], bool]:
    """Refresh one userscript pin."""
    repo = cast("str", pin["repo"])
    branch = cast("str", pin["branch"])
    path = cast("str", pin["path"])
    source_file = cast("str", pin["sourceFile"])
    current_rev = cast("str", pin["rev"])

    commit = github_path_commit(repo, branch, path)
    latest_rev = cast("str", commit["sha"])
    commit_date = cast("str", commit["commit"]["author"]["date"])
    url = raw_github_url(repo, latest_rev, path)
    code = fetch_text(url)
    latest_hash = calculate_url_hash(url)
    latest_meta = parse_userscript_meta(code)

    print(f"{name}:")
    print(f"  Current: {current_rev[:12]} {pin['hash']}")
    print(f"  Latest:  {latest_rev[:12]} {latest_hash}")

    source_changed = save_script_source(PINS_FILE.parent / source_file, code)
    new_pin = {
        **pin,
        "rev": latest_rev,
        "hash": latest_hash,
        "updatedAt": date_to_epoch_ms(commit_date),
        "meta": latest_meta,
    }
    changed = new_pin != pin or source_changed
    print("  Updated" if changed else "  Already up to date")
    return new_pin, changed


def main() -> None:
    """Update all Gecko userscript pins."""
    pins = load_hashes(PINS_FILE)
    changed = False

    for name, pin in list(pins.items()):
        pins[name], pin_changed = update_pin(name, cast("dict[str, Any]", pin))
        changed = changed or pin_changed

    if changed:
        save_hashes(PINS_FILE, pins)


if __name__ == "__main__":
    main()
