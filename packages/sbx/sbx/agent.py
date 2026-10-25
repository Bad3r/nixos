# Copyright (c) 2026 Bad3r
"""Commands through qemu-ga and the parsing of its replies."""

import base64
import binascii
import time
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any, cast

from sbx import journal
from sbx.errors import SbxError
from sbx.model import ExecResult, signal_name

if TYPE_CHECKING:
    from collections.abc import Callable, Sequence

POLL_INTERVAL = 0.2
# The grace between SIGTERM and SIGKILL of a command past its deadline.
GUEST_KILL_AFTER = 5
# How long a command gets to exit after the last signal before sbx stops waiting.
SETTLE = 5
KILL_TIMEOUT = 30
# SIGRTMAX on Linux.
MAX_SIGNAL = 64

# Sends one guest agent command and returns its `return` value.
type Call = Callable[[str, dict[str, object]], object]


def reply_error(detail: str) -> SbxError:
    """Return the error of a malformed qemu-ga reply."""
    msg = f"qemu-ga sent an unexpected reply: {detail}"
    return SbxError(msg, code="agent-reply")


def returned(reply: dict[str, Any], execute: str) -> object:
    """Return the `return` value of a reply."""
    if "return" not in reply:
        msg = f"no return value for {execute}"
        raise reply_error(msg)
    return reply["return"]


def reply_object(value: object, what: str) -> dict[str, Any]:
    """Check that a reply value is an object."""
    if not isinstance(value, dict):
        msg = f"{what} is not an object"
        raise reply_error(msg)
    return cast("dict[str, Any]", value)


def reply_int(value: object, key: str) -> int:
    """Check that a reply value is an integer."""
    if not isinstance(value, int) or isinstance(value, bool):
        msg = f"{key} is not an integer"
        raise reply_error(msg)
    return value


def reply_data(value: object, key: str) -> bytes:
    """Decode a base64 reply value."""
    if not isinstance(value, str):
        msg = f"{key} is not a string"
        raise reply_error(msg)
    try:
        return base64.b64decode(value, validate=True)
    except binascii.Error as error:
        msg = f"{key} is not base64"
        raise reply_error(msg) from error


def guest_holds(reply: dict[str, Any], mac: str, address: str) -> bool:
    """Whether a guest-network-get-interfaces reply puts `address` on the NIC with `mac`."""
    interfaces = reply.get("return")
    if not isinstance(interfaces, list):
        msg = "no interface list"
        raise reply_error(msg)
    for interface in cast("list[object]", interfaces):
        entry = cast("dict[str, object]", reply_object(interface, "an interface"))
        owner = entry.get("hardware-address")
        if not isinstance(owner, str) or owner.lower() != mac.lower():
            continue
        addresses = entry.get("ip-addresses", [])
        if not isinstance(addresses, list):
            msg = "ip-addresses is not a list"
            raise reply_error(msg)
        for item in cast("list[object]", addresses):
            if (
                isinstance(item, dict)
                and cast("dict[str, object]", item).get("ip-address") == address
            ):
                return True
    return False


@dataclass(frozen=True)
class Stop:
    """One step against a command past its deadline: a signal, then a wait for its exit."""

    # Signals the guest process; returns why that failed, or None.
    send: Callable[[int], str | None]
    grace: float


def _optional_int(status: dict[str, Any], key: str) -> int | None:
    value = status.get(key)
    return None if value is None else reply_int(value, key)


def _result(
    status: dict[str, Any], limit: int, duration: float, *, timed_out: bool, killed: bool
) -> ExecResult:
    stdout = reply_data(status.get("out-data", ""), "out-data")
    stderr = reply_data(status.get("err-data", ""), "err-data")
    truncated = bool(status.get("out-truncated") or status.get("err-truncated"))
    truncated = truncated or len(stdout) > limit or len(stderr) > limit
    code = _optional_int(status, "exitcode")
    number = _optional_int(status, "signal")
    if code is None and number is None:
        msg = "guest-exec-status has neither exitcode nor signal"
        raise reply_error(msg)
    if number is not None and not 1 <= number <= MAX_SIGNAL:
        msg = f"signal {number} is no Linux signal"
        raise reply_error(msg)
    return ExecResult(
        code,
        stdout[:limit],
        stderr[:limit],
        truncated,
        timed_out=timed_out,
        signal=None if number is None else signal_name(number),
        killed=killed,
        duration_s=duration,
    )


class GuestExec:
    """guest-exec on one domain, bounded by a deadline on the host's monotonic clock."""

    def __init__(
        self,
        call: Call,
        *,
        clock: Callable[[], float] = time.monotonic,
        pause: Callable[[float], None] = time.sleep,
    ) -> None:
        """Bind the agent channel and the clock the deadline runs on."""
        self._call = call
        self._clock = clock
        self._pause = pause

    def _status(self, pid: int) -> dict[str, Any]:
        status = reply_object(self._call("guest-exec-status", {"pid": pid}), "guest-exec-status")
        if not isinstance(status.get("exited"), bool):
            msg = "exited is not a boolean"
            raise reply_error(msg)
        return status

    def _wait(self, pid: int, until: float | None) -> dict[str, Any] | None:
        """Poll until the process exits, or return None once `until` passes."""
        while True:
            # qemu-ga hands out the output, and forgets the process, only once it exited.
            status = self._status(pid)
            if status["exited"]:
                return status
            if until is not None and self._clock() >= until:
                return None
            self._pause(POLL_INTERVAL)

    def run(  # noqa: PLR0913
        self,
        path: str,
        args: Sequence[str],
        *,
        timeout: float | None,
        limit: int,
        stdin: bytes | None = None,
        stops: Sequence[Stop] = (),
    ) -> ExecResult:
        """Run a program with captured output; past `timeout`, take the `stops` in turn.

        A failure to start raises; a lost channel after the start is a
        transport error in the result, since the command may have run.
        """
        began = self._clock()
        arguments: dict[str, object] = {"path": path, "arg": list(args), "capture-output": True}
        if stdin:
            arguments["input-data"] = base64.b64encode(stdin).decode()
        started = reply_object(self._call("guest-exec", arguments), "guest-exec")
        pid = reply_int(started.get("pid"), "pid")
        deadline = None if timeout is None else began + timeout
        failure = None
        try:
            status = self._wait(pid, deadline)
            if status is not None:
                return _result(status, limit, self._clock() - began, timed_out=False, killed=False)
            for stop in stops:
                failure = stop.send(pid)
                status = self._wait(pid, self._clock() + stop.grace)
                if status is not None:
                    return _result(
                        status, limit, self._clock() - began, timed_out=True, killed=True
                    )
        except SbxError as error:
            if error.code == "agent-reply":
                raise
            expired = deadline is not None and self._clock() >= deadline
            return ExecResult(
                None,
                b"",
                b"",
                timed_out=expired,
                transport_error=f"qemu-ga: {error}",
                duration_s=self._clock() - began,
            )
        note = b""
        if stops:
            detail = failure or f"it still ran {stops[-1].grace:g} s after the last signal"
            journal.record(f"cannot stop guest process {pid}: {detail}", code="kill-failed")
            note = f"sbx: the timed-out process {pid} may still run: {detail}\n".encode()
        return ExecResult(None, b"", note, timed_out=True, duration_s=self._clock() - began)

    def helper(self, path: str, args: Sequence[str]) -> str | None:
        """Run a short helper such as kill; return why it failed, or None."""
        try:
            result = self.run(path, args, timeout=KILL_TIMEOUT, limit=4096)
        except SbxError as error:
            return f"qemu-ga: {error}"
        if result.transport_error is not None:
            return result.transport_error
        if result.exit_code == 0:
            return None
        detail = result.stderr.decode(errors="replace").strip()
        return detail or ("timed out" if result.timed_out else f"exited {result.status()}")

    def group_stops(self) -> tuple[Stop, ...]:
        """SIGTERM to the process group, then SIGKILL after the grace."""

        def signal(name: str) -> Callable[[int], str | None]:
            # The launcher's setsid makes the process group id the guest-exec pid; until it
            # runs, no such group exists, so the signal goes to the launcher itself.
            def send(pid: int) -> str | None:
                script = f"kill -{name} -- -{pid} 2>/dev/null || kill -{name} {pid}"
                return self.helper("/bin/sh", ["-c", script])

            return send

        return (Stop(signal("TERM"), GUEST_KILL_AFTER), Stop(signal("KILL"), SETTLE))
