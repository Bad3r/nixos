#!/usr/bin/env nix-shell
#! nix-shell -i python3 --packages python3
# Copyright (c) 2026 Bad3r

"""Update script for camoufox: the browser release, its paired launcher, fpgen and the model."""

from __future__ import annotations

import argparse
import base64
import io
import json
import re
import sys
import tarfile
import urllib.request
from pathlib import Path
from typing import Any, cast

PACKAGE_NAME = "camoufox"
REPO = "daijro/camoufox"
ASSET = "camoufox-{version}-lin.x86_64.zip"
TAG = re.compile(r"v(\d+(?:\.\d+)*-beta\.\d+)")
MODEL_URL = re.compile(r"https://github\.com/scrapfly/fingerprint-generator/releases/download/.+")
FPGEN_CEILING = (2,)


SCRIPTS_DIR = Path(__file__).resolve().parent.parent.parent / "scripts"
sys.path.insert(0, str(SCRIPTS_DIR))

from updater_bootstrap import bootstrap  # noqa: E402

FLAKE_ROOT, PACKAGE_DIR = bootstrap(__file__, PACKAGE_NAME)
HASHES_FILE = PACKAGE_DIR / "hashes.json"
sys.path.insert(0, str(FLAKE_ROOT / "scripts"))

from updater import fetch_json, load_hashes, save_hashes  # noqa: E402


def sri(hex_digest: str) -> str:
    """Return a sha256 hex digest as an SRI hash."""
    if not re.fullmatch(r"[0-9a-f]{64}", hex_digest):
        msg = f"Unexpected sha256 digest: {hex_digest!r}"
        raise RuntimeError(msg)
    return "sha256-" + base64.b64encode(bytes.fromhex(hex_digest)).decode("ascii")


def latest_release() -> tuple[str, str]:
    """Return the newest stable browser release and its Linux x86_64 asset's sha256.

    Font-bundle releases share the repository, so only vX.Y.Z-beta.N tags count.
    The digest is the one GitHub publishes for the asset, which Camoufox's own
    installer checks the download against (pkgman.py).
    """
    releases = fetch_json(f"https://api.github.com/repos/{REPO}/releases?per_page=30")
    if not isinstance(releases, list):
        msg = "Expected a list of releases from the GitHub API"
        raise TypeError(msg)
    for release in cast("list[dict[str, Any]]", releases):
        match = TAG.fullmatch(str(release.get("tag_name", "")))
        if match is None or release.get("draft") or release.get("prerelease"):
            continue
        version = match.group(1)
        assets = {str(a["name"]): a for a in cast("list[dict[str, Any]]", release["assets"])}
        asset = assets.get(ASSET.format(version=version))
        if asset is None:
            continue
        digest = str(asset.get("digest") or "")
        if not digest.startswith("sha256:"):
            msg = f"GitHub publishes no sha256 for {asset['name']}"
            raise RuntimeError(msg)
        return version, digest.removeprefix("sha256:")
    msg = f"No stable {REPO} release with a Linux x86_64 build"
    raise RuntimeError(msg)


def pypi(name: str) -> dict[str, Any]:
    """Return PyPI's JSON for a project."""
    return cast("dict[str, Any]", fetch_json(f"https://pypi.org/pypi/{name}/json"))


def sdist(release_files: list[dict[str, Any]]) -> dict[str, Any]:
    """Return the source distribution among a release's files."""
    for entry in release_files:
        if entry.get("packagetype") == "sdist":
            return entry
    msg = "The release has no source distribution"
    raise RuntimeError(msg)


def _stable(version: str) -> tuple[int, ...] | None:
    return (
        tuple(int(p) for p in version.split(".")) if re.fullmatch(r"\d+(\.\d+)*", version) else None
    )


def _member_json(archive: tarfile.TarFile, name: str) -> dict[str, Any]:
    """Read one JSON file from an sdist, read by name, never extracted."""
    member = archive.extractfile(name)
    if member is None:
        msg = f"{name} is not a file in the sdist"
        raise RuntimeError(msg)
    return cast("dict[str, Any]", json.load(member))


def paired_library(browser_version: str) -> tuple[str, str, dict[str, Any]]:
    """Return the launcher release paired with the browser, its sdist sha256 and fpgen pin.

    A launcher release names its browser in browser-pin.json; the newest
    stable one naming this browser is taken, and none is an error.
    """
    data = pypi("camoufox")
    versions = sorted(
        (v for v in cast("dict[str, Any]", data["releases"]) if _stable(v)),
        key=lambda v: _stable(v) or (),
        reverse=True,
    )
    for version in versions:
        entry = sdist(cast("list[dict[str, Any]]", data["releases"][version]))
        with urllib.request.urlopen(str(entry["url"]), timeout=60) as response:  # noqa: S310 - PyPI https
            data_bytes = response.read()
        prefix = f"camoufox-{version}/src/camoufox/"
        with tarfile.open(fileobj=io.BytesIO(data_bytes)) as archive:
            pin = _member_json(archive, prefix + "browser-pin.json")
            if pin.get("tag") != f"v{browser_version}":
                continue
            model = _member_json(archive, prefix + "fpgen-model.json")
        return version, str(entry["digests"]["sha256"]), model
    msg = f"No camoufox launcher release on PyPI pairs with browser {browser_version}"
    raise RuntimeError(msg)


def latest_fpgen() -> tuple[str, str]:
    """Return the newest stable fpgen below the launcher's ceiling and its sdist sha256."""
    data = pypi("fpgen")
    versions = [
        v
        for v in cast("dict[str, Any]", data["releases"])
        if (parsed := _stable(v)) is not None and parsed < FPGEN_CEILING
    ]
    version = max(versions, key=lambda v: _stable(v) or ())
    entry = sdist(cast("list[dict[str, Any]]", data["releases"][version]))
    return version, str(entry["digests"]["sha256"])


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--force",
        action="store_true",
        help="re-read every pin even when the browser version is unchanged",
    )
    return parser.parse_args()


def main() -> None:
    """Update the browser, the paired launcher, fpgen and its model pin."""
    args = parse_args()
    data = load_hashes(HASHES_FILE)
    current = str(data["version"])
    latest, digest = latest_release()
    print(f"Current: {current}")
    print(f"Latest:  {latest}")
    if current == latest and not args.force:
        print("Already up to date")
        return

    library, library_digest, model = paired_library(latest)
    model_url = str(model["url"])
    if not MODEL_URL.fullmatch(model_url):
        msg = f"Unexpected fpgen model URL: {model_url}"
        raise RuntimeError(msg)
    fpgen, fpgen_digest = latest_fpgen()
    updated = {
        "version": latest,
        "srcHash": sri(digest),
        "libraryVersion": library,
        "libraryHash": sri(library_digest),
        "fpgenVersion": fpgen,
        "fpgenHash": sri(fpgen_digest),
        "modelUrl": model_url,
        "modelHash": sri(str(model["sha256"])),
    }
    if updated == data:
        print(f"{HASHES_FILE.relative_to(FLAKE_ROOT)} already matches {latest}")
        return
    save_hashes(HASHES_FILE, updated)
    print(f"Updated {HASHES_FILE.relative_to(FLAKE_ROOT)} to {latest} (launcher {library})")


if __name__ == "__main__":
    main()
