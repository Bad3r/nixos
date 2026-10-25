# Copyright (c) 2026 Bad3r
"""Commands in running sandboxes, over SSH on vsock or through qemu-ga."""

import dataclasses
import shlex
import subprocess
from typing import TYPE_CHECKING

from sbx import journal, windows
from sbx.agent import Agent
from sbx.errors import SbxError
from sbx.model import DOMAIN_PREFIX, TIMEOUT_EXIT
from sbx.proc import capture

if TYPE_CHECKING:
    from collections.abc import Sequence

    from sbx.model import DomainInfo, ExecResult


# Grace for the guest's `timeout --kill-after`, and the host backstop beyond it.
GUEST_KILL_AFTER = 5
HOST_BACKSTOP = GUEST_KILL_AFTER + 5


def guest_command(command: Sequence[str], timeout: float | None) -> list[str]:
    """Bound a guest command by coreutils timeout, so it dies with the host's deadline."""
    if timeout is None:
        return list(command)
    return ["timeout", f"--kill-after={GUEST_KILL_AFTER}", f"{timeout:g}", *command]


def _backstop(timeout: float | None) -> float | None:
    return None if timeout is None else timeout + HOST_BACKSTOP


class Execution(Agent):
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

    def exec_capture(
        self,
        name: str,
        command: Sequence[str],
        *,
        timeout: float | None,
        agent: bool,
        token: str | None = None,
    ) -> ExecResult:
        """Run a command and capture its output; with `token`, only in that creation."""
        sandbox = self._running(name, token)
        journal.record(
            f"exec in {name}: {shlex.join(command)}",
            verb="exec",
            sandbox=name,
            session=self.session,
        )
        if self.windows_base(sandbox.meta.base) is not None:
            guest = windows.Guest(self.backend(), sandbox.domain.name)
            return guest.execute(command, timeout=timeout, limit=self.settings.output_limit)
        bounded = guest_command(command, timeout)
        if agent:
            result = self._agent_exec(sandbox.domain.name, bounded, _backstop(timeout))
        else:
            argv = self._ssh(name, sandbox.domain, bounded)
            result = capture(argv, self.settings.output_limit, _backstop(timeout))
        if timeout is not None and result.exit_code == TIMEOUT_EXIT:
            return dataclasses.replace(result, timed_out=True)
        return result

    def exec_attached(
        self, name: str, command: Sequence[str], *, timeout: float | None, token: str | None = None
    ) -> int | None:
        """Run a command with the caller's stdio; return its exit code, or None on timeout."""
        sandbox = self._running(name, token)
        if self.windows_base(sandbox.meta.base) is not None:
            msg = f"sandbox '{name}' runs Windows, which takes commands through qemu-ga only"
            raise SbxError(msg, code="agent-only")
        journal.record(
            f"exec in {name}: {shlex.join(command)}",
            verb="exec",
            sandbox=name,
            session=self.session,
        )
        argv = self._ssh(name, sandbox.domain, guest_command(command, timeout))
        try:
            code = subprocess.run(argv, timeout=_backstop(timeout), check=False).returncode
        except subprocess.TimeoutExpired:
            return None
        return None if timeout is not None and code == TIMEOUT_EXIT else code
