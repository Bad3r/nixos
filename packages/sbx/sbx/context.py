# Copyright (c) 2026 Bad3r
"""Plumbing every sandbox verb shares: the backend, the state lock, and lookups."""

import contextlib
import fcntl
import time
from datetime import UTC, datetime
from typing import TYPE_CHECKING

from sbx import journal
from sbx.errors import SbxError
from sbx.model import DOMAIN_PREFIX, NAME_PATTERN, RESERVED_NAMES, Sandbox
from sbx.net import lease_address

if TYPE_CHECKING:
    from collections.abc import Callable, Generator

    from sbx.config import Paths, Settings
    from sbx.model import Backend
    from sbx.windows import WindowsSettings


def _iso(epoch: float) -> str:
    return datetime.fromtimestamp(epoch, UTC).isoformat(timespec="seconds")


class Context:
    """Settings, paths, the backend, and the lookups of one sandbox."""

    def __init__(
        self,
        settings: Settings,
        paths: Paths,
        connect: Callable[[bool], Backend],
        session: str | None,
        clock: Callable[[], float] = time.time,
    ) -> None:
        """Bind settings and paths; the backend connects on first use."""
        self.settings = settings
        self.paths = paths
        self.session = session
        self._connect = connect
        self._clock = clock
        self._backend: Backend | None = None
        # Polled while a create waits; the MCP server ends the wait of a cancelled call.
        self.cancelled: Callable[[], bool] = lambda: False

    def backend(self, *, require_slice: bool = False) -> Backend:
        """Connect once; starting a guest requires the daemon in sbx.slice."""
        if self._backend is None or require_slice:
            self._backend = self._connect(require_slice)
        return self._backend

    def adopt(self, backend: Backend) -> None:
        """Use a backend connected some other way, such as without starting the daemon."""
        self._backend = backend

    @contextlib.contextmanager
    def locked(self, timeout: float | None = None) -> Generator[None]:
        """Hold the state lock, waiting up to `timeout`; flock is per open file: never nest it."""
        self.paths.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        with self.paths.lock.open("a") as handle:
            if timeout is None:
                fcntl.flock(handle, fcntl.LOCK_EX)
            else:
                deadline = time.monotonic() + timeout
                while True:
                    try:
                        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        break
                    except BlockingIOError:
                        if time.monotonic() >= deadline:
                            msg = f"another sbx command held {self.paths.lock} for {timeout:g} s"
                            raise SbxError(msg, code="busy") from None
                        time.sleep(0.2)
            yield

    def _check_name(self, name: str) -> None:
        if NAME_PATTERN.fullmatch(name) is None or name in RESERVED_NAMES:
            msg = f"'{name}' is not a sandbox name: 1-31 of a-z, 0-9, and -, not 'bases'"
            raise SbxError(msg, code="invalid-name")

    def windows_base(self, base: str) -> WindowsSettings | None:
        """Return the Windows settings when `base` is a Windows base."""
        settings = self.settings.windows
        return settings if settings is not None and base in settings.bases else None

    def agent_only(self, name: str, *, token: str | None = None) -> bool:
        """Return whether a sandbox takes commands through qemu-ga only, as Windows does."""
        return self.windows_base(self.created(name, token).meta.base) is not None

    def has_state(self) -> bool:
        """Return whether any sandbox may exist, without starting the daemon."""
        definitions = self.paths.config / "libvirt" / "qemu"
        return bool(self.paths.sandbox_dirs()) or any(definitions.glob(f"{DOMAIN_PREFIX}*.xml"))

    def owned(self) -> list[Sandbox]:
        """Return the domains sbx created."""
        return [
            Sandbox(domain.name.removeprefix(DOMAIN_PREFIX), domain, domain.meta)
            for domain in self.backend().domains()
            if domain.meta is not None and domain.name.startswith(DOMAIN_PREFIX)
        ]

    def _owned(self, name: str) -> Sandbox | None:
        domain = self.backend().domain(DOMAIN_PREFIX + name)
        if domain is None or domain.meta is None:
            return None
        return Sandbox(name, domain, domain.meta)

    def find(self, name: str) -> Sandbox:
        """Return one sandbox by name."""
        self._check_name(name)
        sandbox = self._owned(name)
        if sandbox is None:
            msg = f"no sandbox named '{name}'"
            raise SbxError(msg, code="not-found")
        return sandbox

    def created(self, name: str, token: str | None) -> Sandbox:
        """Return a sandbox by name, refusing one another create made under that name."""
        sandbox = self.find(name)
        if token is not None and sandbox.meta.token != token:
            msg = f"sandbox '{name}' was destroyed and its name reused"
            raise SbxError(msg, code="replaced")
        return sandbox

    def describe(self, sandbox: Sandbox) -> dict[str, object]:
        """Return the JSON form of one sandbox."""
        domain, meta = sandbox.domain, sandbox.meta
        directory = self.paths.sandbox(sandbox.name)
        return {
            "name": sandbox.name,
            "domain": domain.name,
            "state": domain.state,
            "base": meta.base,
            "net": meta.net,
            "cid": domain.cid,
            "address": self.address(sandbox),
            "memory_mib": domain.memory_mib,
            "cpus": domain.cpus,
            "created": _iso(meta.created),
            "expires": _iso(meta.expires),
            "ttl_left": max(0, meta.expires - int(self._clock())),
            "session": meta.session,
            "token": meta.token,
            "directory": str(directory),
            "xfer": str(directory / "xfer"),
        }

    def address(self, sandbox: Sandbox, *, strict: bool = False) -> str | None:
        """Return the address of a running egress sandbox from the host's DHCP leases.

        A malformed lease file raises only when `strict`; otherwise it is logged
        and the address left out, so one bad file never fails a listing.
        """
        egress = self.settings.egress
        mac = sandbox.domain.mac
        if isinstance(egress, str) or mac is None or not sandbox.domain.active:
            return None
        try:
            return lease_address(egress.leases, mac, self._clock())
        except SbxError as error:
            if strict or error.code != "lease-file":
                raise
            journal.record(f"no address for {sandbox.name}: {error}", code=error.code)
            return None

    def _require_session(self, *, mine: bool) -> None:
        if mine and self.session is None:
            msg = "--mine needs CLAUDE_CODE_SESSION_ID or CODEX_THREAD_ID, or a Codex MCP call"
            raise SbxError(msg, code="no-session")

    def running(self, name: str) -> Sandbox:
        """Return a sandbox that runs within its TTL."""
        return self._running(name)

    def _running(self, name: str, token: str | None = None) -> Sandbox:
        sandbox = self.created(name, token)
        if sandbox.meta.expires <= self._clock():
            msg = f"sandbox '{name}' is past its TTL; `sbx gc` removes it"
            raise SbxError(msg, code="expired")
        if not sandbox.domain.active:
            msg = f"sandbox '{name}' is {sandbox.domain.state}"
            raise SbxError(msg, code="not-running")
        return sandbox
