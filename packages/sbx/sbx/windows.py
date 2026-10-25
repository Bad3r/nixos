# Copyright (c) 2026 Bad3r
"""Windows sandboxes, cloned from an exported golden copy and driven through qemu-ga.

Windows runs no SSH on vsock, so the guest agent carries every command and
file, and the domain gets no vsock device at all.
"""

import base64
import json
import re
import secrets
import shutil
import tarfile
import tempfile
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path, PureWindowsPath
from typing import IO, TYPE_CHECKING, Any, cast

from sbx import core, journal

if TYPE_CHECKING:
    from collections.abc import Sequence

POWERSHELL = r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
TASKKILL = r"C:\Windows\System32\taskkill.exe"
# Where `run --in` copies land.
INBOX = "C:\\sbx\\"
STAGING = r"C:\Windows\Temp"
# Version directories are export times, so their names sort by age.
VERSION_PATTERN = re.compile(r"\d{8}T\d{6}Z")
DISK = "disk.qcow2"
NVRAM = "nvram.fd"
TPM = "tpm"
VARS = "VARS.fd"
FILE_CHUNK = 1 << 20
AGENT_TIMEOUT = 60
OPERATION_TIMEOUT = 600
KILL_TIMEOUT = 30
POLL_INTERVAL = 0.2
HYPERV = (
    "relaxed",
    "vapic",
    "spinlocks",
    "vpindex",
    "runtime",
    "synic",
    "stimer",
    "frequencies",
    "tlbflush",
    "ipi",
)

PREAMBLE = "$ErrorActionPreference = 'Stop'\n$Data = [Console]::In.ReadToEnd() | ConvertFrom-Json\n"
TAR = '& "$env:SystemRoot\\System32\\tar.exe"'
EXTRACT = f"""
try {{
  New-Item -ItemType Directory -Force -Path $Data.destination | Out-Null
  {TAR} -x -f $Data.archive -C $Data.destination
  if ($LASTEXITCODE -ne 0) {{ throw "tar exited $LASTEXITCODE" }}
}} finally {{
  Remove-Item -LiteralPath $Data.archive -Force
}}
"""
PACK = f"""
Get-Item -LiteralPath (Join-Path $Data.parent $Data.leaf) -Force | Out-Null
{TAR} -c -f $Data.archive -C $Data.parent -- $Data.leaf
if ($LASTEXITCODE -ne 0) {{ throw "tar exited $LASTEXITCODE" }}
"""
REMOVE = """
if (Test-Path -LiteralPath $Data.path) { Remove-Item -LiteralPath $Data.path -Force }
"""


@dataclass(frozen=True)
class WindowsSettings:
    """Firmware, defaults, and export directories of the Windows bases."""

    firmware: str
    memory_mib: int
    bases: dict[str, Path]
    export_unit: str

    @classmethod
    def load(cls, raw: dict[str, Any]) -> WindowsSettings:
        """Read the `windows` object of the settings file."""
        bases = cast("dict[str, str]", raw["bases"])
        return cls(
            firmware=raw["firmware"],
            memory_mib=raw["memoryMiB"],
            bases={name: Path(directory) for name, directory in bases.items()},
            export_unit=raw["exportUnit"],
        )

    def unit(self, base: str) -> str:
        """Return the system unit that exports a base."""
        return f"{self.export_unit}@{base}.service"


def versions(directory: Path) -> list[Path]:
    """Return the exports of a base, oldest first; a partial export has a dot name."""
    if not directory.is_dir():
        return []
    return sorted(
        entry
        for entry in directory.iterdir()
        if VERSION_PATTERN.fullmatch(entry.name) and entry.is_dir() and not entry.is_symlink()
    )


def newest(settings: WindowsSettings, base: str) -> Path:
    """Return the newest export of a base."""
    found = versions(settings.bases[base])
    if not found:
        msg = (
            f"Windows base '{base}' has no export; after the golden copy of its guest exists, "
            f"run `systemctl start {settings.unit(base)}` as the owner"
        )
        raise core.SbxError(msg, code="base-missing")
    return found[-1]


def prepare(version: Path, directory: Path) -> None:
    """Give a new sandbox its own NVRAM and TPM state from an export."""
    (directory / "base").symlink_to(version)
    shutil.copyfile(version / NVRAM, directory / VARS)
    (directory / VARS).chmod(0o600)
    shutil.copytree(version / TPM, directory / TPM, copy_function=shutil.copyfile)
    (directory / TPM).chmod(0o700)
    for state in (directory / TPM).iterdir():
        state.chmod(0o600)


def adapt(domain: ET.Element, directory: Path, firmware: str) -> None:
    """Turn the sandbox template into a Windows guest of the golden copy's hardware."""
    domain.remove(_child(domain, "sysinfo"))
    devices = _child(domain, "devices")
    devices.remove(_child(devices, "vsock"))
    # A write past the file size limit fails with EFBIG; stopping keeps it from NTFS.
    _child(_child(devices, "disk"), "driver").set("error_policy", "stop")

    # The golden NVRAM holds enrolled keys, so the code is the firmware it came from.
    system = _child(domain, "os")
    system.clear()
    ET.SubElement(system, "type", arch="x86_64", machine="q35").text = "hvm"
    loader = ET.SubElement(
        system, "loader", {"readonly": "yes", "secure": "yes", "type": "pflash", "format": "raw"}
    )
    loader.text = firmware
    ET.SubElement(system, "nvram", format="raw").text = str(directory / VARS)
    ET.SubElement(system, "boot", dev="hd")

    features = _child(domain, "features")
    hyperv = ET.SubElement(features, "hyperv", mode="custom")
    for name in HYPERV:
        element = ET.SubElement(hyperv, name, state="on")
        if name == "spinlocks":
            element.set("retries", "8191")
    ET.SubElement(features, "smm", state="on")

    clock = _child(domain, "clock")
    clock.clear()
    clock.set("offset", "localtime")
    for name, attributes in (
        ("rtc", {"tickpolicy": "catchup"}),
        ("pit", {"tickpolicy": "delay"}),
        ("hpet", {"present": "no"}),
        ("hypervclock", {"present": "yes"}),
    ):
        ET.SubElement(clock, "timer", {"name": name, **attributes})

    tpm = ET.SubElement(devices, "tpm", model="tpm-crb")
    backend = ET.SubElement(tpm, "backend", type="emulator", version="2.0")
    ET.SubElement(backend, "source", type="dir", path=str(directory / TPM))


def _child(parent: ET.Element, tag: str) -> ET.Element:
    element = parent.find(tag)
    if element is None:
        msg = f"the sandbox template lacks <{tag}>"
        raise core.SbxError(msg, code="internal")
    return element


def guest_path(value: str) -> PureWindowsPath:
    """Parse an absolute guest path, one that names its drive."""
    path = PureWindowsPath(value)
    if not path.is_absolute():
        msg = f"'{value}' is not an absolute Windows path such as C:\\Users\\Public"
        raise core.SbxError(msg, code="invalid-argument")
    return path


def _reply_error(detail: str) -> core.SbxError:
    msg = f"qemu-ga sent an unexpected reply: {detail}"
    return core.SbxError(msg, code="agent-reply")


def _integer(value: object, key: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        msg = f"{key} is not an integer"
        raise _reply_error(msg)
    return value


def _decode(value: object, key: str) -> bytes:
    if not isinstance(value, str):
        msg = f"{key} is not a string"
        raise _reply_error(msg)
    try:
        return base64.b64decode(value, validate=True)
    except ValueError as error:
        msg = f"{key} is not base64"
        raise _reply_error(msg) from error


def _object(value: object, what: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        msg = f"{what} is not an object"
        raise _reply_error(msg)
    return cast("dict[str, Any]", value)


class Guest:
    """The guest agent of one running Windows sandbox."""

    def __init__(self, backend: core.Backend, domain: str) -> None:
        """Bind to a domain."""
        self._backend = backend
        self._domain = domain

    def call(self, execute: str, **arguments: object) -> object:
        """Run one agent command and return its `return` value."""
        command: dict[str, object] = {"execute": execute}
        if arguments:
            command["arguments"] = arguments
        reply = self._backend.agent(self._domain, command, AGENT_TIMEOUT)
        if "return" not in reply:
            msg = f"no return value for {execute}"
            raise _reply_error(msg)
        return reply["return"]

    def execute(
        self,
        command: Sequence[str],
        *,
        timeout: float | None,
        limit: int,
        stdin: bytes = b"",
        kill: bool = True,
    ) -> core.ExecResult:
        """Run a guest program with captured output; a timeout kills its process tree."""
        if not command:
            msg = "give the command after --"
            raise core.SbxError(msg, code="usage")
        arguments: dict[str, object] = {
            "path": command[0],
            "arg": list(command[1:]),
            "capture-output": True,
        }
        if stdin:
            arguments["input-data"] = base64.b64encode(stdin).decode()
        started = _object(self.call("guest-exec", **arguments), "guest-exec")
        pid = _integer(started.get("pid"), "pid")
        deadline = None if timeout is None else time.monotonic() + timeout
        while True:
            status = _object(self.call("guest-exec-status", pid=pid), "guest-exec-status")
            exited = status.get("exited")
            if not isinstance(exited, bool):
                msg = "exited is not a boolean"
                raise _reply_error(msg)
            if exited:
                break
            if deadline is not None and time.monotonic() > deadline:
                note = self._kill(pid) if kill else b""
                return core.ExecResult(None, b"", note, truncated=False, timed_out=True)
            time.sleep(POLL_INTERVAL)
        stdout = _decode(status.get("out-data", ""), "out-data")
        stderr = _decode(status.get("err-data", ""), "err-data")
        truncated = bool(status.get("out-truncated") or status.get("err-truncated"))
        truncated = truncated or len(stdout) > limit or len(stderr) > limit
        code = _integer(status.get("exitcode"), "exitcode")
        return core.ExecResult(code, stdout[:limit], stderr[:limit], truncated, timed_out=False)

    def _kill(self, pid: int) -> bytes:
        """Stop a timed-out process tree; a failure lands in the result's stderr."""
        try:
            result = self.execute(
                [TASKKILL, "/PID", str(pid), "/T", "/F"],
                timeout=KILL_TIMEOUT,
                limit=4096,
                kill=False,
            )
        except core.SbxError as error:
            detail = str(error)
        else:
            if result.exit_code == 0:
                return b""
            detail = result.stderr.decode(errors="replace").strip() or "timed out"
        # taskkill also fails for a process that exited on its own meanwhile.
        if self._exited(pid):
            return b""
        journal.record(f"cannot stop guest process {pid}: {detail}", code="kill-failed")
        return f"sbx: the timed-out process {pid} may still run: {detail}\n".encode()

    def _exited(self, pid: int) -> bool:
        try:
            status = _object(self.call("guest-exec-status", pid=pid), "guest-exec-status")
        except core.SbxError:
            return False
        return status.get("exited") is True

    def powershell(self, script: str, data: dict[str, str]) -> None:
        """Run a PowerShell script with its input on stdin, never in an argument."""
        encoded = base64.b64encode((PREAMBLE + script).encode("utf-16-le")).decode()
        argv = [POWERSHELL, "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded]
        result = self.execute(
            argv, timeout=OPERATION_TIMEOUT, limit=1 << 16, stdin=json.dumps(data).encode()
        )
        if result.timed_out or result.exit_code != 0:
            detail = result.stderr.decode(errors="replace").strip()
            msg = f"a guest operation exited {result.exit_code}: {detail}"
            raise core.SbxError(msg, code="guest-command")

    def _open(self, path: str, mode: str) -> int:
        return _integer(self.call("guest-file-open", path=path, mode=mode), "handle")

    def upload(self, path: str) -> _Upload:
        """Open a guest file for writing."""
        return _Upload(self, self._open(path, "wb"))

    def download(self, path: str, out: IO[bytes], budget: int) -> int:
        """Copy a guest file into `out`, failing once it passes `budget` bytes."""
        handle = self._open(path, "rb")
        total = 0
        try:
            while True:
                reply = _object(
                    self.call("guest-file-read", handle=handle, count=FILE_CHUNK),
                    "guest-file-read",
                )
                data = _decode(reply.get("buf-b64", ""), "buf-b64")
                eof = reply.get("eof") is True
                # Windows signals the end with an empty read, so an empty one without it repeats.
                if not data and not eof:
                    msg = "guest-file-read returned no data before the end of the file"
                    raise _reply_error(msg)
                total += len(data)
                if total > budget:
                    msg = f"the copy passed its {budget >> 20}M budget under the disk cap and floor"
                    raise core.SbxError(msg, code="disk-full")
                out.write(data)
                if eof:
                    return total
        finally:
            self.call("guest-file-close", handle=handle)


class _Upload:
    """A buffered writer into one open guest file, for tarfile's stream mode."""

    def __init__(self, guest: Guest, handle: int) -> None:
        self._guest = guest
        self._handle = handle
        self._buffer = bytearray()

    def write(self, data: bytes) -> int:
        self._buffer += data
        while len(self._buffer) >= FILE_CHUNK:
            self._send(bytes(self._buffer[:FILE_CHUNK]))
            del self._buffer[:FILE_CHUNK]
        return len(data)

    def _send(self, data: bytes) -> None:
        reply = _object(
            self._guest.call(
                "guest-file-write",
                handle=self._handle,
                **{"buf-b64": base64.b64encode(data).decode()},
            ),
            "guest-file-write",
        )
        if _integer(reply.get("count"), "count") != len(data):
            msg = "guest-file-write wrote less than it was sent"
            raise core.SbxError(msg, code="guest-command")

    def close(self) -> None:
        """Send the rest and close the guest file."""
        try:
            if self._buffer:
                self._send(bytes(self._buffer))
                self._buffer.clear()
        finally:
            self._guest.call("guest-file-close", handle=self._handle)


def _staging() -> str:
    return f"{STAGING}\\sbx-{secrets.token_hex(4)}.tar"


def copy_in(guest: Guest, source: Path, destination: str) -> str:
    """Copy a host path into a guest directory, which is created if missing."""
    target = guest_path(destination)
    archive = _staging()
    upload = guest.upload(archive)
    try:
        try:
            # Links were checked against the copy roots, so dereferencing stays inside them.
            with tarfile.open(
                fileobj=cast("IO[bytes]", upload), mode="w|", dereference=True
            ) as tar:
                tar.add(source, arcname=source.name)
        finally:
            upload.close()
    except BaseException:
        guest.powershell(REMOVE, {"path": archive})
        raise
    guest.powershell(EXTRACT, {"archive": archive, "destination": str(target)})
    return str(target)


def copy_out(guest: Guest, source: PureWindowsPath, stage: Path, budget: int) -> None:
    """Copy a guest file or directory into `stage`, refusing links and special files."""
    archive = _staging()
    with tempfile.TemporaryFile(dir=stage) as local:
        try:
            guest.powershell(
                PACK, {"parent": str(source.parent), "leaf": source.name, "archive": archive}
            )
            size = guest.download(archive, local, budget)
        finally:
            guest.powershell(REMOVE, {"path": archive})
        local.seek(0)
        with tarfile.open(fileobj=local, mode="r:") as tar:
            members = tar.getmembers()
            _check_members(members, source.name, budget - size)
            tar.extractall(stage, members=members, filter="data")


def _check_members(members: list[tarfile.TarInfo], leaf: str, room: int) -> None:
    total = 0
    for member in members:
        if member.name != leaf and not member.name.startswith(f"{leaf}/"):
            msg = f"the guest archive holds {member.name!r} outside {leaf!r}"
            raise core.SbxError(msg, code="path-denied")
        if not (member.isreg() or member.isdir()) or member.issparse():
            msg = f"{member.name!r} is not a plain file or directory"
            raise core.SbxError(msg, code="path-denied")
        total += member.size
    if total > room:
        msg = f"the copy passed its {room >> 20}M budget under the disk cap and floor"
        raise core.SbxError(msg, code="disk-full")
