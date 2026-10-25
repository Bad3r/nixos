# Copyright (c) 2026 Bad3r
"""Commands through qemu-ga and the parsing of its replies."""

import base64
import binascii
import time
from typing import TYPE_CHECKING, Any, cast

from sbx.context import Context
from sbx.errors import SbxError
from sbx.model import ExecResult

if TYPE_CHECKING:
    from collections.abc import Sequence


def _agent_error(detail: str) -> SbxError:
    msg = f"qemu-ga sent an unexpected reply: {detail}"
    return SbxError(msg, code="agent-reply")


def _agent_return(reply: dict[str, Any]) -> dict[str, Any]:
    value = reply.get("return")
    if not isinstance(value, dict):
        msg = "no return object"
        raise _agent_error(msg)
    return cast("dict[str, Any]", value)


def _agent_int(status: dict[str, Any], key: str) -> int | None:
    value = status.get(key)
    if value is None:
        return None
    if not isinstance(value, int) or isinstance(value, bool):
        msg = f"{key} is not an integer"
        raise _agent_error(msg)
    return value


def _agent_data(status: dict[str, Any], key: str) -> bytes:
    value = status.get(key, "")
    if not isinstance(value, str):
        msg = f"{key} is not a string"
        raise _agent_error(msg)
    try:
        return base64.b64decode(value, validate=True)
    except binascii.Error as error:
        msg = f"{key} is not base64"
        raise _agent_error(msg) from error


def guest_holds(reply: dict[str, Any], mac: str, address: str) -> bool:
    """Whether a guest-network-get-interfaces reply puts `address` on the NIC with `mac`."""
    interfaces = reply.get("return")
    if not isinstance(interfaces, list):
        msg = "no interface list"
        raise _agent_error(msg)
    for interface in cast("list[object]", interfaces):
        if not isinstance(interface, dict):
            msg = "an interface is not an object"
            raise _agent_error(msg)
        entry = cast("dict[str, object]", interface)
        owner = entry.get("hardware-address")
        if not isinstance(owner, str) or owner.lower() != mac.lower():
            continue
        addresses = entry.get("ip-addresses", [])
        if not isinstance(addresses, list):
            msg = "ip-addresses is not a list"
            raise _agent_error(msg)
        for item in cast("list[object]", addresses):
            if (
                isinstance(item, dict)
                and cast("dict[str, object]", item).get("ip-address") == address
            ):
                return True
    return False


class Agent(Context):
    """Commands run through qemu-ga."""

    def _agent_exec(self, domain: str, command: Sequence[str], timeout: float | None) -> ExecResult:
        backend = self.backend()
        # qemu-ga's PATH omits the system profile, so a login shell resolves the command.
        arguments = {"path": "/bin/sh", "arg": ["-lc", 'exec "$@"', "sbx", *command]}
        started = backend.agent(
            domain,
            {"execute": "guest-exec", "arguments": {**arguments, "capture-output": True}},
            10,
        )
        pid = _agent_int(_agent_return(started), "pid")
        if pid is None:
            msg = "guest-exec returned no pid"
            raise _agent_error(msg)
        deadline = None if timeout is None else self._clock() + timeout
        while True:
            status = _agent_return(
                backend.agent(
                    domain, {"execute": "guest-exec-status", "arguments": {"pid": pid}}, 10
                )
            )
            if not isinstance(status.get("exited"), bool):
                msg = "exited is not a boolean"
                raise _agent_error(msg)
            if status["exited"]:
                break
            if deadline is not None and self._clock() > deadline:
                return ExecResult(None, b"", b"", truncated=False, timed_out=True)
            time.sleep(0.2)
        limit = self.settings.output_limit
        stdout = _agent_data(status, "out-data")
        stderr = _agent_data(status, "err-data")
        truncated = bool(status.get("out-truncated") or status.get("err-truncated"))
        truncated = truncated or len(stdout) > limit or len(stderr) > limit
        code = _agent_int(status, "exitcode")
        signal = _agent_int(status, "signal")
        if code is None and signal is not None:
            code = 128 + signal
        if code is None:
            msg = "guest-exec-status has neither exitcode nor signal"
            raise _agent_error(msg)
        return ExecResult(code, stdout[:limit], stderr[:limit], truncated, timed_out=False)
