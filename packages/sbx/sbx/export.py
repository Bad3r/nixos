# Copyright (c) 2026 Bad3r
"""Export a Windows guest's golden copy as an sbx base.

`export` runs as root and only reads: it opens each golden file and hands the
descriptors to `receive`, which runs as the owner and writes the base, so root
never writes below the owner's home.
"""

import argparse
import errno
import json
import os
import pwd
import re
import shutil
import stat
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from collections.abc import Sequence

VERSION_FORMAT = "%Y%m%dT%H%M%SZ"
VERSION_PATTERN = re.compile(r"\d{8}T\d{6}Z")
NAME_PATTERN = re.compile(r"disk\.qcow2|nvram\.fd|tpm/[A-Za-z0-9._-]+")
SOURCE_RECORD = "source.json"
GIB = 1 << 30
COPY_CHUNK = 1 << 26


class ExportError(Exception):
    """The golden copy cannot be exported."""


def log(message: str) -> None:
    """Print one journal line."""
    print(message, flush=True)


def golden_files(golden: Path, disk: str, guest: str) -> list[tuple[str, Path]]:
    """Map base names to the golden copy's OS disk, NVRAM, and TPM state files."""
    if not golden.is_dir():
        msg = (
            f"{guest} has no golden copy at {golden}; shut it off and run "
            f"`systemctl start workloads-golden@{guest}.service` first"
        )
        raise ExportError(msg)
    files = [("disk.qcow2", golden / disk), ("nvram.fd", golden / "nvram.fd")]
    files += [(f"tpm/{entry.name}", entry) for entry in sorted((golden / "tpm").iterdir())]
    return files


def export(spec: dict[str, Any], guest: str, version: str, receiver: Sequence[str]) -> None:
    """Open the golden files read-only and run the receiver as the owner on them."""
    files = golden_files(Path(spec["golden"]), spec["disk"], guest)
    descriptors: list[int] = []
    try:
        arguments: list[str] = []
        source: list[list[object]] = []
        for name, path in files:
            fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
            descriptors.append(fd)
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode):
                msg = f"{path} is not a regular file"
                raise ExportError(msg)
            arguments.append(f"{fd}:{name}")
            source.append([name, info.st_size, info.st_mtime_ns])
        account = pwd.getpwnam(spec["owner"])
        command = [
            *receiver,
            spec["directory"],
            version,
            "--min-free",
            str(spec["minFreeBytes"]),
            "--source",
            json.dumps(source),
            *arguments,
        ]
        switch: dict[str, Any] = {}
        if account.pw_uid != os.geteuid():
            switch = {"user": account.pw_uid, "group": account.pw_gid, "extra_groups": []}
        subprocess.run(command, check=True, pass_fds=descriptors, umask=0o077, **switch)
    finally:
        for fd in descriptors:
            os.close(fd)


def _allocated(fd: int) -> int:
    return os.fstat(fd).st_blocks * 512


def _copy_range(source: int, target: int, start: int, end: int) -> None:
    position = start
    while position < end:
        count = min(end - position, COPY_CHUNK)
        try:
            copied = os.copy_file_range(source, target, count, position, position)
        except OSError as error:
            if error.errno not in {errno.EXDEV, errno.EINVAL, errno.ENOSYS, errno.EOPNOTSUPP}:
                raise
            data = os.pread(source, count, position)
            copied = os.pwrite(target, data, position) if data else 0
        if copied == 0:
            msg = "a golden file shrank during the export"
            raise ExportError(msg)
        position += copied


def copy_sparse(source: int, target: Path) -> None:
    """Copy an open file's data ranges to a new file, keeping its holes."""
    size = os.fstat(source).st_size
    out = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC, 0o600)
    try:
        offset = 0
        while offset < size:
            try:
                data = os.lseek(source, offset, os.SEEK_DATA)
            except OSError as error:
                if error.errno != errno.ENXIO:
                    raise
                break
            hole = os.lseek(source, data, os.SEEK_HOLE)
            _copy_range(source, out, data, hole)
            offset = hole
        os.ftruncate(out, size)
        os.fsync(out)
    finally:
        os.close(out)


def receive(
    directory: Path,
    version: str,
    files: list[tuple[int, str]],
    source: list[list[object]],
    min_free: int,
) -> Path:
    """Write one export of a base from open golden files, unless the newest matches them."""
    if VERSION_PATTERN.fullmatch(version) is None:
        msg = f"'{version}' is not an export version"
        raise ExportError(msg)
    for _, name in files:
        if NAME_PATTERN.fullmatch(name) is None:
            msg = f"'{name}' is not a base file name"
            raise ExportError(msg)
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    current = sorted(
        entry for entry in directory.iterdir() if VERSION_PATTERN.fullmatch(entry.name)
    )
    record = current[-1] / SOURCE_RECORD if current else None
    if record is not None and record.is_file() and json.loads(record.read_text()) == source:
        log(f"{current[-1]} matches the golden copy; nothing to export")
        return current[-1]
    target = directory / version
    if target.exists():
        msg = f"{target} exists; retry in a second"
        raise ExportError(msg)
    for stale in directory.glob(".partial-*"):
        shutil.rmtree(stale)

    need = sum(_allocated(fd) for fd, _ in files)
    stats = os.statvfs(directory)
    free = stats.f_bavail * stats.f_frsize
    if free - need < min_free:
        msg = (
            f"the export needs {need // GIB}G and would leave {(free - need) // GIB}G free "
            f"on {directory}, below the {min_free // GIB}G floor"
        )
        raise ExportError(msg)

    partial = directory / f".partial-{version}"
    partial.mkdir(mode=0o700)
    try:
        (partial / "tpm").mkdir(mode=0o700)
        for fd, name in files:
            copy_sparse(fd, partial / name)
            (partial / name).chmod(0o400)
        (partial / SOURCE_RECORD).write_text(json.dumps(source))
        partial.rename(target)
    except BaseException:
        shutil.rmtree(partial, ignore_errors=True)
        raise
    log(f"exported the golden copy as {target}")
    return target


def parser() -> argparse.ArgumentParser:
    """Describe the subcommands."""
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    run = commands.add_parser("export", help="export one guest's golden copy, as root")
    run.add_argument("manifest", type=Path)
    run.add_argument("guest")

    accept = commands.add_parser("receive", help="write an export from inherited files")
    accept.add_argument("directory", type=Path)
    accept.add_argument("version")
    accept.add_argument("--min-free", type=int, required=True)
    accept.add_argument("--source", required=True, help="JSON name, size, and mtime per file")
    accept.add_argument("files", nargs="+", metavar="FD:NAME")
    return parser


def _base(manifest: Path, guest: str) -> dict[str, Any]:
    bases: dict[str, dict[str, Any]] = json.loads(manifest.read_text())
    if guest not in bases:
        msg = f"no Windows base is named '{guest}'"
        raise ExportError(msg)
    return bases[guest]


def _descriptor(value: str) -> tuple[int, str]:
    fd, separator, name = value.partition(":")
    if not separator or not fd.isdigit():
        msg = f"'{value}' is not FD:NAME"
        raise ExportError(msg)
    return int(fd), name


def main(argv: Sequence[str] | None = None) -> int:
    """Run the subcommand the arguments name."""
    args = parser().parse_args(argv)
    try:
        if args.command == "export":
            version = datetime.now(UTC).strftime(VERSION_FORMAT)
            receiver = [sys.executable, "-I", sys.argv[0], "receive"]
            export(_base(args.manifest, args.guest), args.guest, version, receiver)
        else:
            files = [_descriptor(value) for value in args.files]
            receive(args.directory, args.version, files, json.loads(args.source), args.min_free)
    except subprocess.CalledProcessError as error:
        print(f"<3>error: the receiver exited {error.returncode}", file=sys.stderr)
        return 1
    except (ExportError, OSError) as error:
        print(f"<3>error: {error}", file=sys.stderr)
        return 1
    return 0
