# Copyright (c) 2026 Bad3r
"""Built, prepared, and exported bases."""

import subprocess
from typing import TYPE_CHECKING

from sbx import cloud, journal, windows
from sbx.errors import SbxError
from sbx.model import FLAVOURS
from sbx.storage import Storage

if TYPE_CHECKING:
    from pathlib import Path


class Bases(Storage):
    """Base images: their lookup, listing, and Nix builds."""

    def base_image(self, base: str) -> Path:
        """Return the qcow2 image of a built, prepared, or exported base."""
        if (windows_settings := self.windows_base(base)) is not None:
            return windows.newest(windows_settings, base) / windows.DISK
        if base in self.settings.cloud_images:
            disk = self.paths.bases / base / cloud.DISK
            if not disk.is_file():
                msg = (
                    f"cloud base '{base}' is not prepared; the owner runs `sbx base prepare {base}`"
                )
                raise SbxError(msg, code="base-missing")
            return disk
        link = self.paths.bases / base
        if not link.exists():
            msg = f"base '{base}' is not built; run `sbx base build {base}`"
            raise SbxError(msg, code="base-missing")
        images = sorted(link.resolve(strict=True).glob("*.qcow2"))
        if len(images) != 1:
            msg = f"{link} holds {len(images)} qcow2 images, expected one"
            raise SbxError(msg, code="base-invalid")
        return images[0]

    def base_list(self) -> list[dict[str, object]]:
        """Report each Nix base's store path and each cloud base's prepared disk."""
        result: list[dict[str, object]] = []
        for flavour in FLAVOURS:
            link = self.paths.bases / flavour
            path = str(link.resolve()) if link.exists() else None
            result.append({"base": flavour, "kind": "nix", "built": path is not None, "path": path})
        for image, pinned in self.settings.cloud_images.items():
            disk = self.paths.bases / image / cloud.DISK
            path = str(disk) if disk.is_file() else None
            result.append(
                {
                    "base": image,
                    "kind": "cloud",
                    "built": path is not None,
                    "path": path,
                    "url": pinned.url,
                }
            )
        if self.settings.windows is not None:
            for base, directory in self.settings.windows.bases.items():
                found = windows.versions(directory)
                result.append(
                    {
                        "base": base,
                        "kind": "windows",
                        "built": bool(found),
                        "path": str(found[-1]) if found else None,
                        "versions": [version.name for version in found],
                    }
                )
        return result

    def base_build(self, flavour: str) -> dict[str, object]:
        """Build a Nix base from the configured flake; its out-link is the GC root."""
        if (windows_settings := self.windows_base(flavour)) is not None:
            msg = (
                f"Windows base '{flavour}' is exported from its guest's golden copy, not built; "
                f"the owner runs `systemctl start {windows_settings.unit(flavour)}`"
            )
            raise SbxError(msg, code="base-export")
        if flavour in self.settings.cloud_images:
            msg = (
                f"cloud base '{flavour}' comes from `sbx base prepare {flavour}`, run by the owner"
            )
            raise SbxError(msg, code="base-cloud")
        if flavour not in FLAVOURS:
            msg = f"unknown base '{flavour}'; bases: {', '.join(FLAVOURS)}"
            raise SbxError(msg, code="unknown-base")
        self.check_disk()
        self.paths.bases.mkdir(mode=0o700, parents=True, exist_ok=True)
        link = self.paths.bases / flavour
        installable = f"{self.settings.flake}#legacyPackages.x86_64-linux.workloads.sbx-{flavour}"
        journal.record(f"building base {flavour} from {installable}", verb="base-build")
        # Build logs go to stderr, which keeps --json output parseable.
        result = subprocess.run(
            [self.settings.tools.nix, "build", "--out-link", str(link), installable],
            stdout=subprocess.DEVNULL,
            check=False,
        )
        if result.returncode != 0:
            msg = f"nix build {installable} exited {result.returncode}"
            raise SbxError(msg, code="build-failed")
        return {"base": flavour, "path": str(link.resolve())}
