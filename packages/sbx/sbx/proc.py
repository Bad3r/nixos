# Copyright (c) 2026 Bad3r
"""Host helper processes: checked runs and bounded captures."""

import subprocess
import threading
from pathlib import Path
from typing import IO, TYPE_CHECKING, NamedTuple

from sbx.errors import SbxError

if TYPE_CHECKING:
    from collections.abc import Sequence


READ_CHUNK = 1 << 16


class Captured(NamedTuple):
    """A helper's exit status, None after its timeout, and its bounded output."""

    code: int | None
    stdout: bytes
    stderr: bytes
    truncated: bool


def run(argv: Sequence[str]) -> str:
    """Run a helper and return its stdout, failing with its stderr."""
    result = subprocess.run(argv, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        msg = f"{Path(argv[0]).name} exited {result.returncode}: {result.stderr.strip()}"
        raise SbxError(msg, code="command-failed")
    return result.stdout


def _drain(stream: IO[bytes], limit: int, sink: list[tuple[bytes, bool]]) -> None:
    data = bytearray()
    truncated = False
    while chunk := stream.read(READ_CHUNK):
        room = limit - len(data)
        if room > 0:
            data += chunk[:room]
        if len(chunk) > room:
            truncated = True
    sink.append((bytes(data), truncated))


def capture(argv: Sequence[str], limit: int, timeout: float | None) -> Captured:
    """Run a command with closed stdin, keeping at most `limit` bytes per stream."""
    out: list[tuple[bytes, bool]] = []
    err: list[tuple[bytes, bool]] = []
    with subprocess.Popen(
        argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    ) as process:
        if process.stdout is None or process.stderr is None:
            msg = "subprocess pipes are missing"
            raise SbxError(msg, code="internal")
        readers = [
            threading.Thread(target=_drain, args=(process.stdout, limit, out)),
            threading.Thread(target=_drain, args=(process.stderr, limit, err)),
        ]
        for reader in readers:
            reader.start()
        try:
            code = process.wait(timeout)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
            code = None
        for reader in readers:
            reader.join()
    return Captured(code, out[0][0], err[0][0], out[0][1] or err[0][1])
