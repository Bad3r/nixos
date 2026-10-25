# Copyright (c) 2026 Bad3r
"""Settings the app module renders, state paths, and parsers of verb arguments."""

import json
import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING

from sbx import windows
from sbx.cloud import CloudImage
from sbx.errors import SbxError
from sbx.model import NAME_PATTERN, RESERVED_NAMES

if TYPE_CHECKING:
    from sbx.windows import WindowsSettings


DURATION_PATTERN = re.compile(r"(\d+)([smhd]?)")
MEMORY_PATTERN = re.compile(r"(\d+)([MG]?)", re.IGNORECASE)
DURATION_UNITS = {"": 1, "s": 1, "m": 60, "h": 3600, "d": 86400}
SESSION_VARIABLES = (("CLAUDE_CODE_SESSION_ID", "claude"), ("CODEX_THREAD_ID", "codex"))


@dataclass(frozen=True)
class Tools:
    """Absolute paths of the programs sbx runs."""

    emulator: str
    qemu_img: str
    ssh: str
    scp: str
    ssh_keygen: str
    socat: str
    tesseract: str
    nsenter: str
    git: str
    systemctl: str
    nix: str
    nix_store: str
    timedatectl: str
    xorriso: str
    virtiofsd: str


@dataclass(frozen=True)
class Egress:
    """The bridge `--net egress` attaches to, the lease file of its DHCP server, and its MTU."""

    bridge: str
    leases: Path
    mtu: int


@dataclass(frozen=True)
class Settings:
    """Ceilings, defaults, and tool paths rendered by the app module."""

    running: int
    memory_mib: int
    sandbox_memory_mib: int
    sandbox_cpus: int
    max_ttl: int
    disk_cap_bytes: int
    min_free_bytes: int
    default_memory_mib: int
    default_gui_memory_mib: int
    default_cpus: int
    default_ttl: int
    disk_gib: int
    cpuset: str
    flake: str
    unit: str
    slice: str
    output_limit: int
    boot_timeout: int
    # Why `--net egress` is unavailable, when it is.
    egress: Egress | str
    cloud_images: dict[str, CloudImage]
    tools: Tools
    # Present when the host exports Windows bases.
    windows: WindowsSettings | None = None
    # The session daemon's file size limit, which every Windows overlay reserves.
    file_bytes: int = 0

    @classmethod
    def load(cls, path: Path) -> Settings:
        """Read the JSON settings file."""
        raw = json.loads(path.read_text())
        if "limits" not in raw:
            msg = "sbx has no settings; enable programs.sbx.extended"
            raise SbxError(msg, code="unconfigured")
        limits = raw["limits"]
        defaults = raw["defaults"]
        return cls(
            running=limits["running"],
            memory_mib=limits["memoryMiB"],
            sandbox_memory_mib=limits["sandboxMemoryMiB"],
            sandbox_cpus=limits["sandboxCpus"],
            max_ttl=limits["ttlSeconds"],
            disk_cap_bytes=limits["diskBytes"],
            min_free_bytes=limits["minFreeBytes"],
            default_memory_mib=defaults["memoryMiB"],
            default_gui_memory_mib=defaults["guiMemoryMiB"],
            default_cpus=defaults["cpus"],
            default_ttl=defaults["ttlSeconds"],
            disk_gib=defaults["diskGiB"],
            cpuset=raw["cpuset"],
            flake=raw["flake"],
            unit=raw["unit"],
            slice=raw["slice"],
            output_limit=raw["outputLimit"],
            boot_timeout=raw["bootTimeout"],
            egress=raw["egress"]
            if isinstance(raw["egress"], str)
            else Egress(
                raw["egress"]["bridge"], Path(raw["egress"]["leases"]), raw["egress"]["mtu"]
            ),
            cloud_images={
                name: CloudImage(image["url"], image["hash"])
                for name, image in raw["cloudImages"].items()
            },
            tools=Tools(**raw["tools"]),
            windows=None
            if raw["windows"] is None
            else windows.WindowsSettings.load(raw["windows"]),
            file_bytes=limits["fileBytes"],
        )


@dataclass(frozen=True)
class Paths:
    """Where sandbox state lives."""

    root: Path
    config: Path

    @classmethod
    def from_environment(cls) -> Paths:
        """Follow the XDG base directories."""
        home = Path.home()
        data = os.environ.get("XDG_DATA_HOME") or str(home / ".local" / "share")
        config = os.environ.get("XDG_CONFIG_HOME") or str(home / ".config")
        return cls(Path(data) / "sbx", Path(config))

    @property
    def bases(self) -> Path:
        """Out-links of built bases, which double as GC roots."""
        return self.root / "bases"

    @property
    def lock(self) -> Path:
        """Serializes ceiling checks against starts and removals."""
        return self.root / ".lock"

    @property
    def queue(self) -> Path:
        """Tickets of creates that wait for capacity."""
        return self.root / ".queue"

    def sandbox(self, name: str) -> Path:
        """Return the run directory of one sandbox."""
        return self.root / name

    def sandbox_dirs(self) -> list[Path]:
        """List local sandbox directories without connecting to libvirt."""
        if not self.root.is_dir():
            return []
        return sorted(
            entry
            for entry in self.root.iterdir()
            if entry.is_dir()
            and not entry.is_symlink()
            and entry.name not in RESERVED_NAMES
            and NAME_PATTERN.fullmatch(entry.name) is not None
        )


def parse_duration(value: str) -> int:
    """Parse `90`, `90s`, `30m`, `2h`, or `1d` into seconds."""
    match = DURATION_PATTERN.fullmatch(value.strip())
    if match is None:
        msg = f"'{value}' is not a duration such as 30m, 2h, or 1d"
        raise SbxError(msg, code="invalid-argument")
    return int(match.group(1)) * DURATION_UNITS[match.group(2)]


def parse_memory(value: str) -> int:
    """Parse `2G`, `512M`, or a bare MiB count into MiB."""
    match = MEMORY_PATTERN.fullmatch(value.strip())
    if match is None:
        msg = f"'{value}' is not a memory size such as 512M or 2G"
        raise SbxError(msg, code="invalid-argument")
    amount = int(match.group(1))
    return amount * 1024 if match.group(2).upper() == "G" else amount


def remote_name(argument: str) -> str | None:
    """Return the sandbox name of an endpoint, allowing an empty guest path."""
    name, separator, _path = argument.partition(":")
    return name if separator and NAME_PATTERN.fullmatch(name) is not None else None


def caller_session() -> str | None:
    """Return the agent session that runs sbx, if any."""
    for variable, client in SESSION_VARIABLES:
        value = os.environ.get(variable)
        if value:
            return f"{client}:{value}"
    return None
