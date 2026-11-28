# Copyright (c) 2026 Bad3r

"""CLI entrypoint for `_patch_agy.py`."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path
from typing import TYPE_CHECKING, Any

from _agy_patcher.elf import Elf64Image, PatchError
from _agy_patcher.patches import ALL, DYNAMIC_PATCHES, apply_edits, plan_edits

if TYPE_CHECKING:
    from collections.abc import Sequence


def _parse_patches(raw: str | None) -> list[str]:
    if raw is None:
        return list(ALL)
    requested = [item.strip() for item in raw.split(",") if item.strip()]
    unknown = [item for item in requested if item not in ALL]
    if unknown:
        msg = f"unknown patch set(s): {','.join(unknown)} (known: {','.join(ALL)})"
        raise PatchError(msg)
    if not requested:
        msg = "--patches requires at least one patch set"
        raise PatchError(msg)
    return [item for item in ALL if item in requested]


def _build_arg_parser() -> argparse.ArgumentParser:
    dyn = ",".join(DYNAMIC_PATCHES)
    parser = argparse.ArgumentParser(
        prog="_patch_agy.py",
        description=(
            f"Write a byte-patched copy of the agy ELF binary. Dynamic discovery supports: {dyn}."
        ),
    )
    parser.add_argument("src", type=Path, help="Unpatched input agy ELF binary.")
    parser.add_argument("dst", type=Path, help="Patched output agy ELF binary.")
    parser.add_argument(
        "--patches",
        default=None,
        help=f"Comma-separated patch sets (default: {','.join(ALL)}).",
    )
    parser.add_argument(
        "--version",
        default=None,
        help="Optional upstream version string recorded in the output manifest.",
    )
    return parser


def run(argv: Sequence[str]) -> dict[str, Any]:
    """Validate, patch, write the patched binary and manifest atomically, and return manifest."""
    args = _build_arg_parser().parse_args(list(argv))
    patches = _parse_patches(args.patches)
    raw = args.src.read_bytes()
    sha = hashlib.sha256(raw).hexdigest()

    elf = Elf64Image(raw)
    edits, discovery_mode, version, discovered = plan_edits(
        elf=elf,
        sha256=sha,
        patches=patches,
        version_hint=args.version,
    )

    buf = bytearray(raw)
    resolved = apply_edits(elf, buf, edits)

    tmp = args.dst.with_name(args.dst.name + ".tmp")
    tmp.write_bytes(buf)
    shutil.copymode(args.src, tmp)
    tmp.replace(args.dst)

    manifest: dict[str, Any] = {
        "input": str(args.src.resolve()),
        "input_sha256": sha,
        "version": version,
        "discovery": discovery_mode,
        "patches": patches,
        "edits": [
            {
                "vaddr": hex(edit.vaddr),
                "offset": hex(off),
                "orig": edit.orig.hex(),
                "new": edit.new.hex(),
            }
            for edit, off in resolved
        ],
        "output": str(args.dst.resolve()),
        "output_sha256": hashlib.sha256(buf).hexdigest(),
    }
    if discovered is not None:
        manifest["discovered"] = discovered

    manifest_path = args.dst.with_name(args.dst.name + ".patch.json")
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


def main(argv: Sequence[str] | None = None) -> None:
    """CLI wrapper translating `PatchError` and OSError into stderr exits."""
    try:
        manifest = run(sys.argv[1:] if argv is None else argv)
    except (PatchError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
    print(json.dumps(manifest, indent=2))
