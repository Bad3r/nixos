#!/usr/bin/env nix-shell
#! nix-shell -i python3 --packages python3
# Copyright (c) 2026 Bad3r

"""Update GrammaTech's prebuilt stable DDisasm and its matching binary libraries."""

from __future__ import annotations

import argparse
import difflib
import json
import re
import sys
import tempfile
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parents[2] / "scripts"
sys.path.insert(0, str(SCRIPTS_DIR))

from updater_bootstrap import bootstrap  # noqa: E402

FLAKE_ROOT, PACKAGE_DIR = bootstrap(__file__, "ddisasm")
PINS_FILE = PACKAGE_DIR / "hashes.json"

from updater import calculate_url_hash, fetch_text, load_hashes  # noqa: E402
from updater.hash import hex_to_sri  # noqa: E402

BASE_URL = "https://download.grammatech.com/gtirb/files/apt-repo/"
STABLE_URL = BASE_URL + "dists/focal/stable/binary-amd64/Packages"
VERSION_PATTERN = re.compile(r"([0-9]+\.[0-9]+\.[0-9]+)-focal")
VENDOR_LIBRARIES = ("libgtirb", "libgtirb-pprinter", "libcapstone-dev")
RUNTIME_PACKAGES = {
    "gcc",
    "libc6",
    "libgcc1",
    "libgcc-s1",
    "libstdc++6",
    "libgomp1",
    "zlib1g",
    "libprotobuf17",
    "libboost-filesystem1.71.0",
    "libboost-program-options1.71.0",
}


def stable_artifacts() -> tuple[str, dict[str, dict[str, str]]]:
    """Select the newest stable Debian artifact and its exact vendor dependencies."""
    records = [
        dict(re.findall(r"^([A-Za-z0-9-]+): (.*)$", stanza, re.MULTILINE))
        for stanza in fetch_text(STABLE_URL).split("\n\n")
    ]
    releases = [
        record
        for record in records
        if record.get("Package") == "ddisasm"
        and VERSION_PATTERN.fullmatch(record.get("Version", ""))
    ]
    if not releases:
        msg = "No stable DDisasm version found in GrammaTech's APT index"
        raise ValueError(msg)
    release = max(
        releases,
        key=lambda record: tuple(map(int, record["Version"].removesuffix("-focal").split("."))),
    )
    selected = {"ddisasm": release}
    for name in VENDOR_LIBRARIES:
        dependency = re.search(
            rf"(?:^|,\s*){re.escape(name)}\s+\(=\s*([^()\s]+)\)",
            release.get("Depends", ""),
        )
        if dependency is None:
            msg = f"Missing exact {name} dependency for DDisasm {release['Version']}"
            raise ValueError(msg)
        matches = [
            record
            for record in records
            if record.get("Package") == name and record.get("Version") == dependency[1]
        ]
        if len(matches) != 1:
            msg = f"Expected one {name} {dependency[1]} artifact, found {len(matches)}"
            raise ValueError(msg)
        selected[name] = matches[0]
    archives: dict[str, dict[str, str]] = {}
    for name, record in selected.items():
        if record.get("Architecture") != "amd64":
            msg = f"{name} is not an amd64 artifact"
            raise ValueError(msg)
        dependencies = set(re.findall(r"(?:^|,\s*)([a-z0-9+.-]+)", record.get("Depends", "")))
        unsupported = dependencies - RUNTIME_PACKAGES - set(VENDOR_LIBRARIES)
        if unsupported:
            msg = f"{name} requires unhandled runtime dependencies: {sorted(unsupported)}"
            raise ValueError(msg)
        filename = record.get("Filename", "")
        if not re.fullmatch(r"pool/stable/[A-Za-z0-9_./+:-]+\.deb", filename) or ".." in filename:
            msg = f"Invalid stable artifact path for {name}: {filename}"
            raise ValueError(msg)
        checksum = record.get("SHA256", "")
        if re.fullmatch(r"[0-9a-f]{64}", checksum) is None:
            msg = f"Invalid SHA256 for {name}"
            raise ValueError(msg)
        archives[name] = {
            "version": record["Version"],
            "url": BASE_URL + filename,
            "hash": hex_to_sri(checksum),
        }
    return release["Version"].removesuffix("-focal"), archives


def write_pins(text: str) -> None:
    """Replace the pin file atomically after every download has succeeded."""
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=PACKAGE_DIR, delete=False) as handle:
            temporary = Path(handle.name)
            handle.write(text)
        temporary.chmod(PINS_FILE.stat().st_mode & 0o777)
        temporary.replace(PINS_FILE)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main() -> None:
    """Refresh the stable binary pins while retaining the fixed Ubuntu ABI libraries."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true", help="verify unchanged artifact hashes")
    parser.add_argument("--dry-run", action="store_true", help="show the update without writing")
    parser.add_argument(
        "--check-release",
        action="store_true",
        help="check stable release metadata without downloading artifacts",
    )
    args = parser.parse_args()
    before = PINS_FILE.read_text(encoding="utf-8")
    pins = load_hashes(PINS_FILE)
    version, archives = stable_artifacts()
    print(f"Current: {pins['version']}")
    print(f"Latest:  {version}")
    if args.check_release:
        print("Stable release metadata is valid")
        return
    for name, archive in (archives | pins["runtime"]).items():
        current = (pins["archives"] | pins["runtime"]).get(name)
        if current == archive and not args.force:
            continue
        actual = calculate_url_hash(archive["url"])
        if actual != archive["hash"]:
            msg = (
                f"{name}: downloaded SHA256 does not match the package index or pinned runtime hash"
            )
            raise ValueError(msg)
        print(f"Verified {name} {archive['version']}")
    updated = {"version": version, "archives": archives, "runtime": pins["runtime"]}
    if updated == pins:
        print("Already up to date")
        return
    after = json.dumps(updated, indent="\t") + "\n"
    if args.dry_run:
        name = str(PINS_FILE.relative_to(FLAKE_ROOT))
        print(
            "".join(
                difflib.unified_diff(
                    before.splitlines(keepends=True),
                    after.splitlines(keepends=True),
                    name,
                    name,
                )
            )
        )
        return
    if PINS_FILE.read_text(encoding="utf-8") != before:
        msg = f"{PINS_FILE} changed during the update; refusing to overwrite it"
        raise RuntimeError(msg)
    write_pins(after)
    print(f"Updated {PINS_FILE.relative_to(FLAKE_ROOT)}")


if __name__ == "__main__":
    main()
