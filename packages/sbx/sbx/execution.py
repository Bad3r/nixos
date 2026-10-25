# Copyright (c) 2026 Bad3r
"""Commands in running sandboxes: captured through qemu-ga, attached over SSH on vsock."""

import shlex
import subprocess
from typing import TYPE_CHECKING

from sbx import journal, windows
from sbx.agent import GUEST_KILL_AFTER, GuestExec, returned
from sbx.context import Context
from sbx.errors import SbxError
from sbx.model import DOMAIN_PREFIX, TIMEOUT_EXIT, TRANSPORT_EXIT, ExecResult
from sbx.proc import capture

if TYPE_CHECKING:
    from collections.abc import Sequence

    from sbx.model import DomainInfo, Sandbox


# The host backstop of an SSH command, beyond the guest's `timeout --kill-after`.
HOST_BACKSTOP = GUEST_KILL_AFTER + 5
AGENT_TIMEOUT = 10
# How `timeout` ends: the command exited on SIGTERM, or SIGKILL followed.
SSH_TIMEOUT_EXITS = {TIMEOUT_EXIT: None, 128 + 9: "KILL", TRANSPORT_EXIT: "KILL"}


def guest_command(command: Sequence[str], timeout: float | None) -> list[str]:
    """Bound an SSH command by coreutils timeout, so it dies with the host's deadline."""
    if timeout is None:
        return list(command)
    return ["timeout", f"--kill-after={GUEST_KILL_AFTER}", f"{timeout:g}", *command]


def agent_command(command: Sequence[str]) -> list[str]:
    """Start a qemu-ga command as a session leader, so its pid names its process group."""
    # qemu-ga's PATH omits the system profile, so a login shell resolves the command.
    return ["/bin/sh", "-lc", 'exec setsid -w -- "$@"', "sbx", *command]


def _backstop(timeout: float | None) -> float | None:
    return None if timeout is None else timeout + HOST_BACKSTOP


def ssh_result(  # noqa: PLR0913
    code: int | None,
    elapsed: float,
    timeout: float | None,
    stdout: bytes = b"",
    stderr: bytes = b"",
    *,
    truncated: bool = False,
) -> ExecResult:
    """Read the exit status of `ssh ... timeout ... CMD`; only the host clock says timed out."""
    if code is None:
        return ExecResult(
            None, stdout, stderr, truncated, timed_out=True, killed=True, duration_s=elapsed
        )
    if timeout is not None and elapsed >= timeout and code in SSH_TIMEOUT_EXITS:
        return ExecResult(
            None,
            stdout,
            stderr,
            truncated,
            timed_out=True,
            signal=SSH_TIMEOUT_EXITS[code],
            killed=True,
            duration_s=elapsed,
        )
    if code == TRANSPORT_EXIT:
        # ssh exits 255 on a failed connection and on a command killed by a signal alike.
        error = "ssh exited 255: the connection failed, or the command died by a signal"
        return ExecResult(
            None, stdout, stderr, truncated, transport_error=error, duration_s=elapsed
        )
    return ExecResult(code, stdout, stderr, truncated, duration_s=elapsed)


class Execution(Context):
    """Commands run in a sandbox, captured or attached."""

    def _ssh_options(self, name: str, domain: DomainInfo) -> list[str]:
        if domain.cid is None or domain.pid is None:
            msg = f"sandbox '{name}' has no vsock CID; is it running?"
            raise SbxError(msg, code="not-running")
        directory = self.paths.sandbox(name)
        tools = self.settings.tools
        # The guest's CID exists only in the namespace its QEMU runs in.
        proxy = (
            f"{tools.nsenter} --target {domain.pid} --user --net --preserve-credentials -- "
            f"{tools.socat} - VSOCK-CONNECT:{domain.cid}:22"
        )
        options = {
            "IdentitiesOnly": "yes",
            "IdentityAgent": "none",
            "BatchMode": "yes",
            "StrictHostKeyChecking": "accept-new",
            "UserKnownHostsFile": str(directory / "known_hosts"),
            "GlobalKnownHostsFile": "/dev/null",
            "HostKeyAlias": DOMAIN_PREFIX + name,
            "ProxyCommand": proxy,
            "ConnectTimeout": "10",
            "ControlMaster": "no",
            "ControlPath": "none",
            "LogLevel": "ERROR",
        }
        argv = ["-F", "/dev/null", "-i", str(directory / "id_ed25519")]
        for key, value in options.items():
            argv += ["-o", f"{key}={value}"]
        return argv

    def _ssh(self, name: str, domain: DomainInfo, command: Sequence[str]) -> list[str]:
        options = self._ssh_options(name, domain)
        return [self.settings.tools.ssh, *options, "-T", "root@sbx", "--", shlex.join(command)]

    def windows_guest(self, domain: str) -> windows.Guest:
        """Return the guest agent of a Windows sandbox, on this context's clock."""
        return windows.Guest(self.backend(), domain, clock=self.monotonic, pause=self.pause)

    def _guest_exec(self, domain: str) -> GuestExec:
        backend = self.backend()

        def call(execute: str, arguments: dict[str, object]) -> object:
            command: dict[str, object] = {"execute": execute, "arguments": arguments}
            return returned(backend.agent(domain, command, AGENT_TIMEOUT), execute)

        return GuestExec(call, clock=self.monotonic, pause=self.pause)

    def _record(self, name: str, command: Sequence[str]) -> None:
        journal.record(
            f"exec in {name}: {shlex.join(command)}",
            verb="exec",
            sandbox=name,
            session=self.session,
        )

    def exec_capture(
        self,
        name: str,
        command: Sequence[str],
        *,
        timeout: float | None,
        token: str | None = None,
    ) -> ExecResult:
        """Capture a command through qemu-ga; with `token`, only in that creation."""
        sandbox = self._running(name, token)
        self._record(name, command)
        limit = self.settings.output_limit
        if self.windows_base(sandbox.meta.base) is not None:
            guest = self.windows_guest(sandbox.domain.name)
            return guest.execute(command, timeout=timeout, limit=limit)
        guest = self._guest_exec(sandbox.domain.name)
        argv = agent_command(command)
        return guest.run(argv[0], argv[1:], timeout=timeout, limit=limit, stops=guest.group_stops())

    def ssh_capture(
        self, sandbox: Sandbox, command: Sequence[str], *, timeout: float | None
    ) -> ExecResult:
        """Capture a command over SSH, for a guest without qemu-ga such as a cloud image."""
        argv = self._ssh(sandbox.name, sandbox.domain, guest_command(command, timeout))
        began = self.monotonic()
        code, stdout, stderr, truncated = capture(
            argv, self.settings.output_limit, _backstop(timeout)
        )
        elapsed = self.monotonic() - began
        return ssh_result(code, elapsed, timeout, stdout, stderr, truncated=truncated)

    def exec_attached(
        self, name: str, command: Sequence[str], *, timeout: float | None, token: str | None = None
    ) -> ExecResult:
        """Run a command over SSH with the caller's stdio; the result carries no output."""
        sandbox = self._running(name, token)
        if self.windows_base(sandbox.meta.base) is not None:
            msg = f"sandbox '{name}' runs Windows, which takes commands through qemu-ga only"
            raise SbxError(msg, code="agent-only")
        self._record(name, command)
        argv = self._ssh(name, sandbox.domain, guest_command(command, timeout))
        began = self.monotonic()
        try:
            code = subprocess.run(argv, timeout=_backstop(timeout), check=False).returncode
        except subprocess.TimeoutExpired:
            code = None
        return ssh_result(code, self.monotonic() - began, timeout)
