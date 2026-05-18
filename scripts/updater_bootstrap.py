"""Bootstrap helpers for package update scripts."""

from __future__ import annotations

import socket
from pathlib import Path


def _flake_root(start: Path, package_name: str) -> Path | None:
    """Walk up from ``start`` until this checkout's flake root is found."""
    for parent in [start, *start.parents]:
        if (
            (parent / "flake.nix").is_file()
            and (parent / "scripts" / "updater").is_dir()
            and (parent / "packages" / package_name / "default.nix").is_file()
        ):
            return parent
    return None


def checkout_root(script_file: str | Path, package_name: str) -> Path:
    """Find the editable checkout from either cwd or the script path."""
    starts = [
        Path.cwd().resolve(),
        Path(script_file).resolve().parent,
    ]
    for start in starts:
        root = _flake_root(start, package_name)
        if root is not None:
            return root

    msg = (
        "Could not find the nixos checkout root. Run this updater from the "
        "repository checkout, or execute the checkout copy under "
        f"packages/{package_name}/."
    )
    raise RuntimeError(msg)


def bootstrap(script_file: str | Path, package_name: str) -> tuple[Path, Path]:
    """Return the checkout root and package directory for an update script."""
    flake_root = checkout_root(script_file, package_name)
    return flake_root, flake_root / "packages" / package_name


def current_hostname() -> str:
    """Return the current host name as used by flake host attributes."""
    return socket.gethostname().split(".", 1)[0]


def host_package_attr(flake_root: Path, package_name: str) -> str:
    """Return the current host overlay-aware package attribute."""
    hostname = current_hostname()
    return f"{flake_root}#nixosConfigurations.{hostname}.pkgs.{package_name}"
