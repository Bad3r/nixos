# Copyright (c) 2026 Bad3r
"""Creating, booting, and destroying sandboxes."""

import contextlib
import json
import secrets
import shutil
import signal
import threading
import time
from typing import TYPE_CHECKING

from sbx import cloud, journal, windows
from sbx.admission import Admission
from sbx.agent import guest_holds
from sbx.bases import Bases
from sbx.cleanup import Cleanup
from sbx.domain import DomainXml
from sbx.errors import SbxError
from sbx.execution import Execution
from sbx.model import CREATION_FILE, DOMAIN_PREFIX, GIB, Meta
from sbx.net import random_mac
from sbx.proc import capture, run

if TYPE_CHECKING:
    from collections.abc import Generator
    from pathlib import Path

    from sbx.model import Request, Sandbox


@contextlib.contextmanager
def _terminate_raises() -> Generator[None]:
    """Turn SIGTERM into SystemExit in the main thread, so cleanups run as on SIGINT."""
    if threading.current_thread() is not threading.main_thread():
        yield
        return

    def terminate(signum: int, _frame: object) -> None:
        raise SystemExit(128 + signum)

    previous = signal.signal(signal.SIGTERM, terminate)
    try:
        yield
    finally:
        signal.signal(signal.SIGTERM, previous)


class Lifecycle(Admission, Bases, DomainXml, Execution, Cleanup):
    """Sandboxes from create to destroy."""

    def _sandbox_key(self, name: str, directory: Path) -> str:
        """Generate the sandbox's SSH key and return its public half."""
        key = directory / "id_ed25519"
        comment = DOMAIN_PREFIX + name
        run(
            [
                self.settings.tools.ssh_keygen,
                "-q",
                "-t",
                "ed25519",
                "-N",
                "",
                "-C",
                comment,
                "-f",
                str(key),
            ]
        )
        return key.with_suffix(".pub").read_text().strip()

    def create(self, request: Request, *, token: str | None = None) -> dict[str, object]:
        """Start a sandbox and wait until it accepts commands.

        The creation token, the caller's or a fresh one, marks the domain and
        run directory and comes back as `token`.
        """
        token = token or secrets.token_hex(8)
        self._validate(request)
        name = request.name or f"{request.base}-{secrets.token_hex(3)}"
        self._check_name(name)
        image = self.base_image(request.base)
        # Prepared cloud disks and Windows exports live outside the store.
        outside = request.base in self.settings.cloud_images or self.windows_base(request.base)
        root = None if outside else image.parent
        with _terminate_raises():
            return self._start(request, name, image, token, root=root, agent=True)

    def _start(  # noqa: PLR0913
        self,
        request: Request,
        name: str,
        image: Path,
        token: str,
        *,
        root: Path | None,
        agent: bool,
    ) -> dict[str, object]:
        """Boot `name` on an overlay of `image`, which `root` keeps alive, and wait for it."""
        directory = self.paths.sandbox(name)
        with self._admitted(request, name) as backend:
            windows_settings = self.windows_base(request.base)
            if windows_settings is not None:
                # gc prunes superseded exports under this lock, so pick the newest only here.
                image = windows.newest(windows_settings, request.base) / windows.DISK
            tools = self.settings.tools
            info = json.loads(run([tools.qemu_img, "info", "-U", "--output=json", str(image)]))
            size = max(int(info["virtual-size"]), self.settings.disk_gib * GIB)
            linux_size = size if windows_settings is None else self.settings.disk_gib * GIB
            active = [sandbox.meta.base for sandbox in self.owned() if sandbox.domain.active]
            # Every running overlay may still grow to its full virtual size, or a Windows
            # one, whose disk is larger, to the daemon's file size limit.
            self.check_disk(
                reserve=sum(
                    self.settings.file_bytes if self.windows_base(base) else linux_size
                    for base in [*active, request.base]
                )
            )
            nic = (self._check_egress(), random_mac()) if request.net == "egress" else None
            now = int(self._clock())
            meta = Meta(
                request.base,
                str(image),
                request.net,
                now,
                now + request.ttl,
                self.session,
                token,
            )
            directory.mkdir(mode=0o700)
            try:
                (directory / CREATION_FILE).write_text(token)
                (directory / "xfer").mkdir(mode=0o700)
                if windows_settings is None:
                    public = self._sandbox_key(name, directory)
                else:
                    public = ""
                    windows.prepare(image.parent, directory)
                if root is not None:
                    # A per-sandbox root keeps the base through a rebuild and a GC.
                    gc_root = str(directory / "base")
                    run([tools.nix_store, "--add-root", gc_root, "--realise", str(root)])
                disk = str(directory / "disk.qcow2")
                run(
                    [
                        tools.qemu_img,
                        "create",
                        "-q",
                        "-f",
                        "qcow2",
                        "-F",
                        "qcow2",
                        "-b",
                        str(image),
                        disk,
                        str(size),
                    ]
                )
                if request.base in self.settings.cloud_images:
                    seed_nic = None if nic is None else (nic[1], nic[0].mtu)
                    self._write_seed(name, directory, public, nic=seed_nic)
                backend.start(self._domain_xml(name, directory, meta, request, public, nic))
            except BaseException:
                self._discard(name, token)
                raise
        journal.record(
            f"created sandbox {name}",
            verb="create",
            sandbox=name,
            base=request.base,
            session=self.session,
        )
        try:
            self._wait_ready(name, token, agent=agent)
        except BaseException:
            with self.locked():
                self._discard(name, token)
            raise
        return self.describe(self.created(name, token))

    def _console_tail(self, name: str) -> str:
        path = self.paths.sandbox(name) / "console.log"
        try:
            lines = path.read_text(errors="replace").splitlines()
        except FileNotFoundError:
            return ""
        return "\n".join(lines[-15:])

    def _write_seed(
        self, name: str, directory: Path, public_key: str, *, nic: tuple[str, int] | None
    ) -> None:
        """Pack the NoCloud seed; a fresh instance id makes cloud-init run again."""
        instance = f"{DOMAIN_PREFIX}{name}-{secrets.token_hex(4)}"
        files = directory / "seed"
        files.mkdir(mode=0o700)
        for leaf, content in cloud.seed_files(instance, public_key, nic=nic).items():
            (files / leaf).write_text(content)
        run(
            [
                self.settings.tools.xorriso,
                "-as",
                "mkisofs",
                "-quiet",
                "-output",
                str(directory / cloud.SEED),
                "-volid",
                "cidata",
                "-joliet",
                "-rock",
                str(files),
            ]
        )
        shutil.rmtree(files)

    def _wait_ready(self, name: str, token: str, *, agent: bool) -> None:
        """Wait for qemu-ga, SSH on vsock, and an egress lease; without `agent`, SSH only."""
        # Monotonic, so a host sleep during the boot wait does not count against it.
        deadline = time.monotonic() + self.settings.boot_timeout
        domain = DOMAIN_PREFIX + name
        while agent:
            self.created(name, token)
            try:
                self.backend().agent(domain, {"execute": "guest-ping"}, 5)
                break
            except SbxError:
                if time.monotonic() > deadline:
                    tail = self._console_tail(name)
                    msg = f"the guest agent of '{name}' did not answer; console:\n{tail}"
                    raise SbxError(msg, code="boot-timeout") from None
                time.sleep(1)
        if self.agent_only(name, token=token):
            return
        while True:
            sandbox = self.created(name, token)
            result = capture(self._ssh(name, sandbox.domain, ["true"]), 4096, 30)
            if result.exit_code == 0:
                break
            if time.monotonic() > deadline:
                detail = result.stderr.decode(errors="replace").strip()
                msg = f"ssh over vsock to '{name}' failed: {detail}"
                raise SbxError(msg, code="boot-timeout")
            time.sleep(1)
        # The address check asks qemu-ga; a prepare boot's script waits for the network itself.
        if agent and sandbox.meta.net == "egress":
            self._wait_address(sandbox, deadline)

    def _wait_address(self, sandbox: Sandbox, deadline: float) -> None:
        name, mac = sandbox.name, sandbox.domain.mac
        while True:
            address = self.address(sandbox, strict=True)
            # dnsmasq records the lease before the guest's ARP probe ends and it configures it.
            if address is not None and mac is not None:
                command: dict[str, object] = {"execute": "guest-network-get-interfaces"}
                reply = self.backend().agent(sandbox.domain.name, command, 5)
                if guest_holds(reply, mac, address):
                    return
            if time.monotonic() > deadline:
                if address is None:
                    msg = f"'{name}' got no DHCP lease on its egress bridge; console:\n"
                else:
                    msg = f"'{name}' never configured its lease {address}; console:\n"
                raise SbxError(msg + self._console_tail(name), code="no-address")
            time.sleep(1)

    def destroy(self, name: str) -> list[str]:
        """Remove one sandbox."""
        self._check_name(name)
        with self.locked():
            known = any(sandbox.name == name for sandbox in self.owned())
            if not known and not self.paths.sandbox(name).is_dir():
                msg = f"no sandbox named '{name}'"
                raise SbxError(msg, code="not-found")
            self._discard(name)
        journal.record(f"destroyed sandbox {name}", verb="destroy", sandbox=name)
        return [name]

    def destroy_created(self, token: str) -> list[str]:
        """Remove the sandboxes whose metadata carries `token`."""
        if not self.has_state():
            return []
        with self.locked():
            removed = [sandbox.name for sandbox in self.owned() if sandbox.meta.token == token]
            for name in removed:
                self._discard(name, token)
        for name in removed:
            journal.record(f"destroyed sandbox {name}", verb="destroy", sandbox=name)
        return removed

    def destroy_where(
        self, *, mine: bool, expired: bool, timeout: float | None = None
    ) -> list[str]:
        """Remove the caller's sandboxes or the expired ones; `timeout` bounds the lock wait."""
        self._require_session(mine=mine)
        if expired and not self.host_synced():
            msg = (
                "the host clock is not NTP-synchronized, so TTLs cannot be judged; destroy by name"
            )
            raise SbxError(msg, code="clock-unsynced")
        if not self.has_state():
            return []
        removed: list[str] = []
        now = self._clock()
        with self.locked(timeout):
            for sandbox in self.owned():
                meta = sandbox.meta
                if (mine and meta.session == self.session) or (expired and meta.expires <= now):
                    self._discard(sandbox.name)
                    removed.append(sandbox.name)
        for name in removed:
            journal.record(f"destroyed sandbox {name}", verb="destroy", sandbox=name)
        return removed
