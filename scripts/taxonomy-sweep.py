#!/usr/bin/env python3

"""Generate metadata overrides for taxonomy validation.

This script walks one or more package manifests (JSON arrays of package names)
and emits two artefacts:

* `lib/taxonomy/metadata-overrides.json`: canonical metadata entries for
  packages that do not expose AppStream metadata upstream.
* `build/taxonomy/metadata-overrides-review.json`: a review queue highlighting
  asset-heavy packages and other heuristics that may need manual curation.

The script prefers curated metadata (see `CURATED_OVERRIDES`) and skips
packages that already ship `.desktop` files in the local mirrors
(`/home/vx/git/nixpkgs`, `/home/vx/git/home-manager`, `nixos_docs_md`).

Usage:

    ./scripts/taxonomy-sweep.py [--manifest path.json ...]

If no manifest is provided, the script reads
`docs/RFC-0001/manifest-registry.json`.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple

REPO_ROOT = Path(__file__).resolve().parents[1]

# Mirrors containing desktop files for detection.
DESKTOP_SEARCH_ROOTS = [
    Path("/home/vx/git/nixpkgs"),
    Path("/home/vx/git/home-manager"),
    REPO_ROOT / "nixos_docs_md",
]

DEFAULT_MANIFEST_REGISTRY = REPO_ROOT / "docs/RFC-0001/manifest-registry.json"
OVERRIDES_PATH = REPO_ROOT / "lib/taxonomy/metadata-overrides.json"
REVIEW_PATH = REPO_ROOT / "build/taxonomy/metadata-overrides-review.json"

# Curated entries override all heuristics.
CURATED_OVERRIDES: Dict[str, Dict[str, object]] = {
    "system76-wallpapers": {
        "canonicalAppStreamId": "System",
        "categories": ["System", "Settings"],
        "auxiliaryCategories": ["Graphics"],
        "secondaryTags": ["asset", "hardware-integration"],
        "reason": "System76 wallpapers ship without AppStream metadata.",
    },
    "prettier": {
        "canonicalAppStreamId": "Development",
        "categories": ["Development"],
        "auxiliaryCategories": ["Utility"],
        "secondaryTags": ["formatter", "cli"],
        "reason": "CLI formatter packaged without AppStream/AppData information.",
    },
}

ASSET_KEYWORDS = {
    "Graphics": ["icon", "wallpaper", "cursor", "font", "theme", "emoji"],
    "AudioVideo": ["sound-theme", "ringtone"],
    "System": ["locale", "manpage", "docs", "documentation"],
}

DEV_KEYWORDS = {
    "python",
    "pip",
    "uv",
    "node",
    "npm",
    "yarn",
    "rust",
    "cargo",
    "go",
    "gcc",
    "clang",
    "cmake",
    "meson",
    "ninja",
    "make",
    "gdb",
    "lldb",
    "docker",
    "kubectl",
    "terraform",
    "ansible",
    "gradle",
    "maven",
    "java",
    "kotlin",
    "clj",
    "lein",
    "ruby",
    "rails",
    "php",
    "composer",
    "formatter",
    "linter",
    "eslint",
    "prettier",
    "shellcheck",
    "cabal",
    "stack",
    "dev",
    "sdk",
    "builder",
    "lint",
    "fmt",
    "wasm",
    "llvm",
    "git",
    "mercurial",
    "bazel",
    "bazelisk",
    "bazel"
}

NETWORK_KEYWORDS = {
    "ssh",
    "vpn",
    "wireguard",
    "network",
    "curl",
    "http",
    "wget",
    "ftp",
    "rsync",
    "proxy",
    "cloudflare",
    "tailscale",
    "zerotier",
    "tor",
    "dns",
    "whois",
}

SYSTEM_KEYWORDS = {
    "kernel",
    "udev",
    "systemd",
    "hardware",
    "firmware",
    "boot",
    "grub",
    "btrfs",
    "zfs",
    "ntfs",
    "lvm",
    "nvme",
    "udisks",
    "upower",
    "powertop",
    "fwupd",
    "pam",
    "security",
    "selinux",
    "apparmor",
    "audit",
    "usb",
    "bluetooth",
    "printer",
    "cups",
    "disk",
    "backup",
    "timeshift",
    "cron",
    "system76",
    "pipewire",
    "pulseaudio",
    "alsa",
    "virt",
    "qemu",
    "libvirt",
    "hyper",
    "qmk",
    "scdaemon",
}


def load_registry_entries(manifest_args: Sequence[str]):
    if manifest_args:
        return [
            {
                "host": None,
                "manifest": Path(p).resolve(),
            }
            for p in manifest_args
        ]

    raw = json.loads(DEFAULT_MANIFEST_REGISTRY.read_text())
    entries = []
    for item in raw:
        if isinstance(item, str):
            entries.append({
                "host": None,
                "manifest": (REPO_ROOT / Path(item)).resolve(),
            })
            continue
        if isinstance(item, dict):
            manifest = item.get("manifest")
            if manifest is None:
                raise ValueError("Registry entry missing 'manifest'")
            entries.append({
                "host": item.get("host"),
                "manifest": (REPO_ROOT / Path(manifest)).resolve(),
            })
            continue
        raise ValueError("Registry entries must be strings or objects with 'manifest'")
    return entries


def read_packages(entries) -> List[str]:
    packages: List[str] = []
    for entry in entries:
        path = entry["manifest"]
        data = json.loads(path.read_text())
        if not isinstance(data, list):
            raise ValueError(f"Manifest {path} must be a JSON array")
        packages.extend([str(item) for item in data])
    return sorted(set(packages))


def build_desktop_index() -> Dict[str, List[str]]:
    index: Dict[str, List[str]] = {}
    for root in DESKTOP_SEARCH_ROOTS:
        if not root.exists():
            continue
        for path in root.rglob("*.desktop"):
            key = path.stem.lower()
            entry = index.setdefault(key, [])
            entry.append(str(path))
    return index


def has_desktop(pkg: str, index: Dict[str, List[str]]) -> bool:
    key = pkg.lower()
    if key in index:
        return True
    # Also match hyphen-separated names against dotted desktop filenames.
    alt = key.replace("-", "")
    return any(alt in stem for stem in index.keys())


def classify_asset(pkg: str) -> Tuple[str, List[str], List[str]] | None:
    name = pkg.lower()
    for root, keywords in ASSET_KEYWORDS.items():
        if any(keyword in name for keyword in keywords):
            aux = [] if root == "System" else ["Utility"]
            tags = ["asset"]
            return root, aux, tags
    return None


def classify_cli(pkg: str) -> Tuple[str, List[str], List[str]]:
    name = pkg.lower()

    def contains(keywords: Iterable[str]) -> bool:
        return any(keyword in name for keyword in keywords)

    if contains(DEV_KEYWORDS):
        return "Development", ["Utility"], ["cli"]
    if contains(NETWORK_KEYWORDS):
        return "Network", ["System"], ["cli"]
    if contains(SYSTEM_KEYWORDS):
        return "System", ["Utility"], ["cli"]
    return "Utility", [], ["cli"]


def classify(pkg: str) -> Dict[str, object]:
    asset = classify_asset(pkg)
    if asset:
        canonical, aux, tags = asset
        metadata: Dict[str, object] = {
            "canonicalAppStreamId": canonical,
            "categories": [canonical],
            "secondaryTags": tags,
            "reason": "Asset package without AppStream metadata detected by heuristics.",
        }
        if aux:
            metadata["auxiliaryCategories"] = aux
        return metadata

    canonical, aux, tags = classify_cli(pkg)
    metadata = {
        "canonicalAppStreamId": canonical,
        "categories": [canonical],
        "secondaryTags": tags,
        "reason": "Auto-generated CLI override (no AppStream metadata detected in local mirrors).",
    }
    if aux:
        metadata["auxiliaryCategories"] = aux
    return metadata


def merge_overrides(packages: Sequence[str], desktop_index: Dict[str, List[str]]) -> Tuple[Dict[str, Dict[str, object]], List[Dict[str, object]]]:
    overrides: Dict[str, Dict[str, object]] = {}
    review_queue: List[Dict[str, object]] = []

    for pkg in packages:
        if pkg in CURATED_OVERRIDES:
            data = CURATED_OVERRIDES[pkg]
            overrides[pkg] = data
            review_queue.append({"package": pkg, "source": "curated", "metadata": data})
            continue

        if has_desktop(pkg, desktop_index):
            continue

        metadata = classify(pkg)
        overrides[pkg] = metadata

        if "asset" in metadata.get("secondaryTags", []):
            review_queue.append({"package": pkg, "source": "asset-heuristic", "metadata": metadata})

    return overrides, review_queue


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", dest="manifests", action="append", help="Path to a manifest JSON file (can be repeated).")
    args = parser.parse_args(argv)

    entries = load_registry_entries(args.manifests or [])
    packages = read_packages(entries)

    desktop_index = build_desktop_index()
    overrides, review_queue = merge_overrides(packages, desktop_index)

    # Always include curated overrides even if their packages are absent (for future runs).
    for pkg, data in CURATED_OVERRIDES.items():
        overrides.setdefault(pkg, data)

    overrides_json = json.dumps(dict(sorted(overrides.items(), key=lambda item: item[0].lower())), indent=2)
    OVERRIDES_PATH.write_text(overrides_json + "\n")

    if review_queue:
        REVIEW_PATH.parent.mkdir(parents=True, exist_ok=True)
        REVIEW_PATH.write_text(json.dumps(review_queue, indent=2) + "\n")
    elif REVIEW_PATH.exists():
        REVIEW_PATH.unlink()


if __name__ == "__main__":
    main()
