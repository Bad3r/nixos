"""Hashes file I/O utilities for Nix package updaters."""

import json
from typing import TYPE_CHECKING, Any, cast

if TYPE_CHECKING:
    from pathlib import Path


def load_hashes(path: Path) -> dict[str, Any]:
    """Load hashes.json file.

    Args:
        path: Path to hashes.json file

    Returns:
        Parsed JSON data as dictionary

    """
    return cast("dict[str, Any]", json.loads(path.read_text()))


def save_hashes(path: Path, data: dict[str, Any]) -> None:
    """Save hashes.json with consistent formatting.

    Args:
        path: Path to hashes.json file
        data: Dictionary to save

    """
    path.write_text(json.dumps(data, indent="\t") + "\n")
