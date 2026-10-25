# Copyright (c) 2026 Bad3r
"""Cloud bases, provisioned by one boot with egress."""

import json
import secrets
import shutil
import time
from pathlib import Path

from sbx import cloud, journal
from sbx.errors import SbxError
from sbx.lifecycle import Lifecycle
from sbx.model import Request
from sbx.proc import run

# The prepare boot's lifetime must outlast its provisioning timeout.
PREPARE_TTL = 3600
PREPARE_TIMEOUT = 1800
SHUTDOWN_TIMEOUT = 120


class Prepare(Lifecycle):
    """`sbx base prepare`, which boots a pinned cloud image to provision it."""

    def base_prepare(self, image: str) -> dict[str, object]:
        """Boot a pinned cloud image once with egress and keep its provisioned disk as a base."""
        if self.session is not None:
            msg = (
                "`sbx base prepare` boots an internet image with egress, "
                "so the owner runs it outside agent sessions"
            )
            raise SbxError(msg, code="owner-only")
        pinned = self.settings.cloud_images.get(image)
        if pinned is None:
            known = ", ".join(self.settings.cloud_images)
            msg = f"unknown cloud base '{image}'; cloud bases: {known}"
            raise SbxError(msg, code="unknown-base")
        name = cloud.PREPARE_PREFIX + image
        self._check_name(name)
        self.check_disk()
        self._check_egress()
        with self.locked():
            self._check_unused(image, name)
        journal.record(f"preparing base {image} from {pinned.url}", verb="base-prepare", base=image)
        fetched = run(
            [
                self.settings.tools.nix,
                "store",
                "prefetch-file",
                "--json",
                "--expected-hash",
                pinned.hash,
                pinned.url,
            ]
        )
        source = Path(json.loads(fetched)["storePath"])
        self._check_image(source)
        settings = self.settings
        request = Request(
            image, name, "egress", settings.default_memory_mib, settings.default_cpus, PREPARE_TTL
        )
        token = secrets.token_hex(8)
        # A failed start discards its own sandbox; a name another prepare holds stays.
        self._start(request, name, source, token, root=source, agent=False)
        try:
            result = self.exec_capture(
                name,
                ["sh", "-c", cloud.PREPARE_SCRIPT],
                timeout=PREPARE_TIMEOUT,
                agent=False,
                token=token,
            )
            if result.exit_code != 0:
                detail = result.stderr.decode(errors="replace").strip()[-2000:]
                status = "timed out" if result.timed_out else f"exited {result.exit_code}"
                msg = f"provisioning {image} {status}: {detail}"
                raise SbxError(msg, code="prepare-failed")
            # Unlocked, so sleep and other verbs proceed during the shutdown and the flatten.
            self._wait_shutoff(name, token)
            disk = self._publish_base(image, name, token)
        finally:
            with self.locked():
                self._discard(name, token)
        journal.record(f"prepared base {image}", verb="base-prepare", base=image)
        return {"base": image, "path": str(disk), "url": pinned.url, "hash": pinned.hash}

    def _check_image(self, path: Path) -> None:
        """Refuse an image whose header makes QEMU open another host file."""
        # The pinned hash only proves the file is the one first trusted.
        # A forced format makes qemu-img fail on anything but qcow2.
        command = [self.settings.tools.qemu_img, "info", "--output=json", "-f", "qcow2", str(path)]
        try:
            info = json.loads(run(command))
        except SbxError as error:
            msg = f"{path} is not a readable qcow2 image: {error}"
            raise SbxError(msg, code="image-unsafe") from error
        problems: list[str] = []
        if backing := info.get("backing-filename"):
            problems.append(f"backing file {backing!r}")
        if data := info.get("format-specific", {}).get("data", {}).get("data-file"):
            problems.append(f"data file {data!r}")
        if problems:
            msg = f"{path} names {', '.join(problems)}; sbx boots only self-contained qcow2 images"
            raise SbxError(msg, code="image-unsafe")

    def _check_unused(self, image: str, prepare: str) -> None:
        users = [
            sandbox.name
            for sandbox in self.owned()
            if sandbox.meta.base == image and sandbox.name != prepare
        ]
        if users:
            msg = f"sandboxes {', '.join(users)} run on base {image}; destroy them first"
            raise SbxError(msg, code="base-in-use")

    def _wait_shutoff(self, name: str, token: str) -> None:
        deadline = time.monotonic() + SHUTDOWN_TIMEOUT
        while self.created(name, token).domain.active:
            if time.monotonic() > deadline:
                msg = f"'{name}' did not power off within {SHUTDOWN_TIMEOUT}s"
                raise SbxError(msg, code="prepare-failed")
            time.sleep(1)

    def _publish_base(self, image: str, name: str, token: str) -> Path:
        """Flatten the shut-off prepare boot's disk into the base, replacing an older one."""
        bases = self.paths.bases
        bases.mkdir(mode=0o700, parents=True, exist_ok=True)
        staged = bases / f".{image}-{secrets.token_hex(4)}"
        staged.mkdir(mode=0o700)
        overlay = staged / "overlay.qcow2"
        target = bases / image
        try:
            # gc takes shut-off sandboxes, so the disk leaves the run directory under the lock.
            with self.locked():
                self.created(name, token)
                (self.paths.sandbox(name) / "disk.qcow2").rename(overlay)
            flat = staged / cloud.DISK
            run(
                [
                    self.settings.tools.qemu_img,
                    "convert",
                    "-q",
                    "-O",
                    "qcow2",
                    str(overlay),
                    str(flat),
                ]
            )
            overlay.unlink()
            flat.chmod(0o400)
            with self.locked():
                self._check_unused(image, name)
                if target.exists():
                    old = bases / f".{image}-{secrets.token_hex(4)}"
                    target.rename(old)
                    shutil.rmtree(old)
                staged.rename(target)
        finally:
            if staged.exists():
                shutil.rmtree(staged)
        return target / cloud.DISK
