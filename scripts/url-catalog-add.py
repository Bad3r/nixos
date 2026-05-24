#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "ruamel.yaml>=0.18.10",
# ]
# ///
# USAGE: EDITOR='uv run --script scripts/url-catalog-add.py' sops secrets/url-catalog.yaml

"""Interactively append an entry to the encrypted URL catalog YAML shape."""

from __future__ import annotations

import argparse
import io
import os
import re
import sys
import tempfile
from datetime import date
from pathlib import Path
from urllib.parse import urlparse

from ruamel.yaml import YAML
from ruamel.yaml.comments import CommentedMap, CommentedSeq
from ruamel.yaml.scalarstring import DoubleQuotedScalarString


DEFAULT_PATH = Path("secrets/decrypted_url_catalog.yaml")
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
DOMAIN_RE = re.compile(
    r"^(?=.{1,253}$)(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+"
    r"[a-zA-Z][a-zA-Z0-9-]{1,62}\.?$"
)
STATUSES = ("active", "unknown", "broken", "deprecated")


def color_enabled() -> bool:
    return sys.stdout.isatty() and os.environ.get("NO_COLOR") is None


COLOR = color_enabled()
RESET = "\033[0m"
STYLE = {
    "prompt": "\033[36m",
    "hint": "\033[2m",
    "error": "\033[31m",
    "success": "\033[32m",
    "header": "\033[1;35m",
    "path": "\033[33m",
}


def styled(value: object, style: str) -> str:
    text = str(value)
    if not COLOR:
        return text
    return f"{STYLE[style]}{text}{RESET}"


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "path",
        nargs="?",
        help="Catalog YAML path. SOPS supplies this automatically when used as EDITOR.",
    )
    parser.add_argument(
        "-f",
        "--file",
        type=Path,
        help=f"Catalog YAML path (default: {DEFAULT_PATH}).",
    )
    parser.add_argument(
        "--no-confirm",
        action="store_true",
        help="Append without showing the final confirmation prompt.",
    )
    return parser.parse_args(argv)


def make_yaml() -> YAML:
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.indent(mapping=2, sequence=4, offset=2)
    yaml.width = 100
    return yaml


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return re.sub(r"-{2,}", "-", slug)


def prompt_text(label: str, *, default: str | None = None, required: bool = False) -> str:
    suffix = styled(f" [{default}]", "hint") if default not in (None, "") else ""
    while True:
        value = input(f"{styled(label, 'prompt')}{suffix}: ").strip()
        if value:
            return value
        if default is not None:
            return default
        if not required:
            return ""
        print(styled("Value required.", "error"))


def prompt_bool(label: str, *, default: bool) -> bool:
    hint = "Y/n" if default else "y/N"
    while True:
        value = input(f"{styled(label, 'prompt')} {styled(f'[{hint}]', 'hint')}: ").strip().lower()
        if not value:
            return default
        if value in {"y", "yes", "true", "1"}:
            return True
        if value in {"n", "no", "false", "0"}:
            return False
        print(styled("Enter yes or no.", "error"))


def prompt_choice(label: str, choices: tuple[str, ...], *, default: str) -> str:
    joined = ", ".join(choices)
    while True:
        value = prompt_text(f"{label} ({joined})", default=default)
        if value in choices:
            return value
        print(styled(f"Choose one of: {joined}", "error"))


def prompt_url(label: str, *, required: bool) -> str:
    while True:
        value = prompt_text(label, required=required)
        if not value and not required:
            return ""
        if is_url(value):
            return value
        print(
            styled(
                "Enter a URL or domain, for example example.org or https://example.invalid.",
                "error",
            )
        )


def is_url(value: str) -> bool:
    value = value.strip()
    if not value or any(char.isspace() for char in value):
        return False

    parsed = urlparse(value)
    if parsed.scheme:
        return bool(parsed.netloc or parsed.path)

    host = value.split("/", 1)[0].rsplit("@", 1)[-1].split(":", 1)[0]
    return bool(DOMAIN_RE.fullmatch(host))


def parse_tags(value: str) -> CommentedSeq:
    tags = CommentedSeq()
    seen: set[str] = set()
    for raw in value.split(","):
        tag = raw.strip()
        if tag and tag not in seen:
            tags.append(tag)
            seen.add(tag)
    return tags


def q(value: str) -> DoubleQuotedScalarString:
    return DoubleQuotedScalarString(value)


def prompt_id(existing_ids: set[str], title: str) -> str:
    default = slugify(title)
    while True:
        entry_id = prompt_text("Entry id", default=default, required=True)
        if not ID_RE.fullmatch(entry_id):
            print(
                styled(
                    "Use lowercase letters, digits, and hyphens. Start with a letter or digit.",
                    "error",
                )
            )
            continue
        if entry_id in existing_ids:
            print(styled(f"Entry id already exists: {entry_id}", "error"))
            continue
        return entry_id


def load_catalog(path: Path, yaml: YAML) -> CommentedMap:
    if not path.exists():
        return initial_catalog()

    data = yaml.load(path.read_text())
    if data is None:
        return initial_catalog()
    if not isinstance(data, CommentedMap):
        raise SystemExit("Catalog root must be a YAML mapping.")
    if "sops" in data:
        raise SystemExit(
            "File looks encrypted. Open it with sops or decrypt to a temporary file first."
        )
    entries = data.get("entries")
    if not isinstance(entries, list):
        raise SystemExit("Catalog field `entries` must be a YAML list.")
    return data


def initial_catalog() -> CommentedMap:
    catalog = CommentedMap()
    catalog["schema_version"] = 1
    catalog["owner"] = "vx"
    catalog["updated_at"] = q(date.today().isoformat())
    catalog["entries"] = CommentedSeq()
    return catalog


def existing_ids(catalog: CommentedMap) -> set[str]:
    ids: set[str] = set()
    for entry in catalog.get("entries", []):
        if isinstance(entry, dict):
            entry_id = entry.get("id")
            if isinstance(entry_id, str):
                ids.add(entry_id)
    return ids


def prompt_mirrors() -> CommentedSeq:
    mirrors = CommentedSeq()
    while True:
        mirror_url = prompt_url("Mirror URL (blank to finish)", required=False)
        if not mirror_url:
            break
        mirror = CommentedMap()
        mirror["url"] = mirror_url
        mirror["description"] = prompt_text("Mirror description", required=False)
        mirrors.append(mirror)
    return mirrors


def prompt_entry(catalog: CommentedMap) -> CommentedMap:
    title = prompt_text("Title", required=True)
    entry_id = prompt_id(existing_ids(catalog), title)

    entry = CommentedMap()
    entry["id"] = entry_id
    entry["title"] = title
    entry["description"] = prompt_text("Description", required=True)
    entry["primary_url"] = prompt_url("Primary URL", required=True)
    entry["tags"] = parse_tags(prompt_text("Tags (comma-separated)", default=""))

    auth = CommentedMap()
    auth["method"] = prompt_text("Auth method", default="none", required=True)
    auth["notes"] = prompt_text("Auth notes", default="")
    entry["auth"] = auth

    entry["mirrors"] = prompt_mirrors()

    verification = CommentedMap()
    status = prompt_choice("Verification status", STATUSES, default="active")
    verification["last_checked"] = None if status == "unknown" else q(date.today().isoformat())
    verification["status"] = status
    verification["notes"] = prompt_text("Verification notes", default="")
    entry["verification"] = verification

    return entry


def is_non_decrypted_secret_path(path: Path) -> bool:
    try:
        resolved = path.resolve()
        secrets_dir = Path("secrets").resolve()
        return resolved.is_relative_to(secrets_dir) and not path.name.startswith("decrypted_")
    except OSError as err:
        raise SystemExit(f"Cannot resolve target path: {path}: {err}") from err


def require_plaintext_confirmation(path: Path) -> None:
    if not is_non_decrypted_secret_path(path):
        return
    if prompt_bool(
        "Target is a non-decrypted path under secrets. Write plaintext there",
        default=False,
    ):
        return
    raise SystemExit("Aborted before writing plaintext to a secrets path.")


def render_entry(entry: CommentedMap, yaml: YAML) -> str:
    stream = io.StringIO()
    yaml.dump(entry, stream)
    return stream.getvalue().rstrip()


def write_catalog(path: Path, catalog: CommentedMap, yaml: YAML) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode if path.exists() else None
    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=path.parent,
        prefix=f".{path.name}.",
        delete=False,
    ) as tmp:
        temp_path = Path(tmp.name)
        yaml.dump(catalog, tmp)
    if mode is not None:
        os.chmod(temp_path, mode)
    os.replace(temp_path, path)


def target_path(args: argparse.Namespace) -> Path:
    if args.file is not None:
        return args.file
    if args.path:
        return Path(args.path)
    return DEFAULT_PATH


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    path = target_path(args)
    yaml = make_yaml()
    catalog = load_catalog(path, yaml)

    require_plaintext_confirmation(path)

    entry = prompt_entry(catalog)
    print()
    print(styled("Entry preview:", "header"))
    print(render_entry(entry, yaml))
    print()

    if not args.no_confirm and not prompt_bool("Append this entry", default=True):
        print("No changes made.")
        return 0

    entries = catalog["entries"]
    if not isinstance(entries, list):
        raise SystemExit("Catalog field `entries` must be a YAML list.")
    entries.append(entry)
    catalog["updated_at"] = q(date.today().isoformat())
    write_catalog(path, catalog, yaml)
    print(f"{styled('Added entry', 'success')} `{entry['id']}` to {styled(path, 'path')}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\nInterrupted. No changes written.", file=sys.stderr)
        raise SystemExit(130)
