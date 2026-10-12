#!/usr/bin/env -S uv run --script
# Copyright (c) 2026 Bad3r
# /// script
# requires-python = ">=3.14"
# dependencies = []
# ///
"""Reconcile Windows guest firewall and virtiofs policy without restarting its VM."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import cast

type Json = bool | int | float | str | list[Json] | dict[str, Json] | None
type Object = dict[str, Json]

CHUNK_SIZE = 48 * 1024
NEEDS_APPLY = 10
POWERSHELL = r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"


def object_value(value: Json) -> Object:
    """Reject malformed protocol objects."""
    if not isinstance(value, dict):
        msg = "Expected a JSON object"
        raise TypeError(msg)
    return value


def string_value(value: Json) -> str:
    """Reject missing or malformed string fields."""
    if not isinstance(value, str):
        msg = "Expected a JSON string"
        raise TypeError(msg)
    return value


def integer_value(value: Json) -> int:
    """Reject noninteger file handles, counts and process IDs."""
    if type(value) is not int:
        msg = "Expected a JSON integer"
        raise ValueError(msg)
    return value


def ps_quote(value: str) -> str:
    """Quote a literal for PowerShell rather than interpolating executable text."""
    return "'" + value.replace("'", "''") + "'"


def file_hash(path: Path) -> str:
    """Hash a pinned payload without retaining an open file descriptor."""
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


class Agent:
    """Send bounded guest-agent requests through the configured libvirt URI."""

    def __init__(self, virsh: str, uri: str, domain: str) -> None:
        """Bind all requests to the declared domain."""
        self.command = [virsh, "--connect", uri]
        self.domain = domain

    def virsh(self, *arguments: str) -> str:
        """Run virsh with a deadline and retain its error on failure."""
        result = subprocess.run(
            [*self.command, *arguments],
            capture_output=True,
            text=True,
            check=False,
            timeout=20,
            env={"LC_ALL": "C"},
        )
        if result.returncode:
            msg = f"virsh {arguments[0]} failed: {result.stderr.strip()}"
            raise RuntimeError(msg)
        return result.stdout.strip()

    def request(self, execute: str, arguments: Object | None = None) -> Json:
        """Validate the envelope before exposing an agent response."""
        command: Object = {"execute": execute}
        if arguments is not None:
            command["arguments"] = arguments
        raw = self.virsh("qemu-agent-command", self.domain, json.dumps(command), "--timeout", "10")
        response = object_value(cast("Json", json.loads(raw)))
        if "error" in response:
            msg = f"{execute} failed: {json.dumps(response['error'])}"
            raise RuntimeError(msg)
        if "return" not in response:
            msg = f"{execute} returned no result"
            raise ValueError(msg)
        return response["return"]

    def powershell(self, command: str, *, timeout: float = 600) -> tuple[int, str]:
        """Wait for one process, without resubmitting an uncertain execution."""
        command = (
            "$ProgressPreference = 'SilentlyContinue'; "
            "[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); " + command
        )
        encoded = base64.b64encode(command.encode("utf-16-le")).decode("ascii")
        result = object_value(
            self.request(
                "guest-exec",
                {
                    "path": POWERSHELL,
                    "arg": [
                        "-NoLogo",
                        "-NoProfile",
                        "-NonInteractive",
                        "-ExecutionPolicy",
                        "Bypass",
                        "-EncodedCommand",
                        encoded,
                    ],
                    "capture-output": True,
                },
            )
        )
        pid = integer_value(result.get("pid"))
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            status = object_value(self.request("guest-exec-status", {"pid": pid}))
            if status.get("exited") is True:
                output = [
                    base64.b64decode(string_value(status[field]), validate=True)
                    .decode("utf-8-sig", errors="replace")
                    .strip()
                    for field in ("out-data", "err-data")
                    if field in status
                ]
                if status.get("out-truncated") or status.get("err-truncated"):
                    msg = f"Guest PowerShell output was truncated (PID {pid})"
                    raise RuntimeError(msg)
                return integer_value(status.get("exitcode")), "\n".join(output).strip()
            time.sleep(1)
        msg = f"Guest PowerShell PID {pid} timed out; the guest mutex prevents overlapping setup"
        raise TimeoutError(msg)

    def write_file(self, destination: str, data: bytes) -> None:
        """Transfer binary data, handling short writes and closing on failure."""
        handle = integer_value(self.request("guest-file-open", {"path": destination, "mode": "wb"}))
        try:
            offset = 0
            while offset < len(data):
                chunk = data[offset : offset + CHUNK_SIZE]
                response = object_value(
                    self.request(
                        "guest-file-write",
                        {"handle": handle, "buf-b64": base64.b64encode(chunk).decode("ascii")},
                    )
                )
                count = integer_value(response.get("count"))
                if not 0 < count <= len(chunk):
                    msg = f"Invalid guest write count {count} for {destination}"
                    raise RuntimeError(msg)
                offset += count
        finally:
            self.request("guest-file-close", {"handle": handle})


def checked_powershell(agent: Agent, command: str) -> str:
    """Surface a guest process failure together with its captured diagnostic."""
    code, output = agent.powershell(command)
    if code:
        msg = f"Guest PowerShell failed ({code}): {output}"
        raise RuntimeError(msg)
    return output


def reconcile_guest_services_firewall(agent: Agent, script_path: Path, staging: str) -> None:
    """Converge the bounded inbound service rule and retain guest failures."""
    guest_script = staging + r"\guest-services-firewall.ps1"
    agent.write_file(guest_script, script_path.read_bytes())
    command = f"$ErrorActionPreference = 'Stop'; & {ps_quote(guest_script)} -Mode "
    code, output = agent.powershell(command + "Probe; exit $LASTEXITCODE")
    if code == 0:
        print(output)
    elif code == NEEDS_APPLY:
        print(f"Windows guest firewall setup needed: {output}", flush=True)
        print(checked_powershell(agent, command + "Apply; exit $LASTEXITCODE"))
    else:
        msg = f"Windows guest firewall probe failed ({code}): {output}"
        raise RuntimeError(msg)


def reconcile(config: Object, agent: Agent) -> None:
    """Inspect real state before transferring payloads or invoking installation."""
    state = agent.virsh("domstate", agent.domain)
    if state != "running":
        print(f"Windows guest provisioning deferred: guest is {state}")
        return
    domain = ET.fromstring(agent.virsh("dumpxml", agent.domain))  # noqa: S314
    filesystems = domain.findall("./devices/filesystem")
    if not any(
        fs.find("driver[@type='virtiofs']") is not None
        and fs.find("target[@dir='transfer']") is not None
        and (source := fs.find("source")) is not None
        and source.get("dir") == string_value(config.get("transfer_dir"))
        for fs in filesystems
    ):
        msg = "Active guest lacks the declared virtiofs share; fully shut Windows down and start it"
        raise RuntimeError(msg)
    info = object_value(agent.request("guest-info"))
    commands = info.get("supported_commands")
    if not isinstance(commands, list):
        msg = "Guest agent did not report its enabled commands"
        raise TypeError(msg)
    enabled = {
        string_value(item.get("name"))
        for command in commands
        if (item := object_value(command)).get("enabled") is True
        and isinstance(item.get("name"), str)
    }
    required = {
        "guest-exec",
        "guest-exec-status",
        "guest-file-open",
        "guest-file-write",
        "guest-file-close",
    }
    if missing := required - enabled:
        msg = f"Enable these QEMU guest-agent commands: {', '.join(sorted(missing))}"
        raise RuntimeError(msg)
    root = checked_powershell(
        agent,
        "$ErrorActionPreference = 'Stop'; "
        r"$root = Join-Path $env:ProgramFiles 'NixOS\VirtioFS'; "
        "$null = New-Item -ItemType Directory -Force -Path (Join-Path $root 'staging'); "
        "[Console]::WriteLine($root)",
    )
    if not root.startswith("C:\\Program Files\\") or "\n" in root or "\r" in root:
        msg = f"Unexpected guest provisioning directory: {root!r}"
        raise ValueError(msg)
    payloads = {
        name: Path(string_value(path)) for name, path in object_value(config.get("files")).items()
    }
    manifest: Object = {
        "winfsp_version": config.get("winfsp_version"),
        "hashes": {name: file_hash(path) for name, path in payloads.items()},
    }
    staging = root + r"\staging"
    agent.write_file(staging + r"\manifest.json", json.dumps(manifest).encode("ascii"))
    agent.write_file(
        staging + r"\shared-folder.ps1", Path(string_value(config.get("script"))).read_bytes()
    )
    reconcile_guest_services_firewall(
        agent,
        Path(string_value(config.get("guest_services_firewall_script"))),
        staging,
    )

    command = (
        "$ErrorActionPreference = 'Stop'; "
        f"& {ps_quote(staging + chr(92) + 'shared-folder.ps1')} "
        f"-ManifestPath {ps_quote(staging + chr(92) + 'manifest.json')} -Mode "
    )
    code, output = agent.powershell(command + "Probe; exit $LASTEXITCODE")
    if code == 0:
        print(output)
    elif code != NEEDS_APPLY:
        msg = f"Windows filesystem probe failed ({code}): {output}"
        raise RuntimeError(msg)
    else:
        print(f"Windows filesystem setup needed: {output}", flush=True)
        for name, path in payloads.items():
            agent.write_file(staging + "\\" + name, path.read_bytes())
        print(checked_powershell(agent, command + "Apply; exit $LASTEXITCODE"))
    agent.write_file(
        staging + r"\pin-quick-access.ps1", payloads["pin-quick-access.ps1"].read_bytes()
    )
    agent.write_file(
        staging + r"\quick-access.ps1",
        Path(string_value(config.get("quick_access_script"))).read_bytes(),
    )
    print(
        checked_powershell(
            agent,
            "$ErrorActionPreference = 'Stop'; "
            f"& {ps_quote(staging + chr(92) + 'quick-access.ps1')} "
            f"-ManifestPath {ps_quote(staging + chr(92) + 'manifest.json')}; exit $LASTEXITCODE",
        )
    )


def main() -> int:
    """Read the Nix-produced declaration and return an observable failure."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path)
    arguments = parser.parse_args()
    try:
        config = object_value(cast("Json", json.loads(arguments.config.read_text())))
        agent = Agent(
            string_value(config.get("virsh")),
            string_value(config.get("uri")),
            string_value(config.get("domain")),
        )
        reconcile(config, agent)
    except (
        OSError,
        TypeError,
        ValueError,
        RuntimeError,
        ET.ParseError,
        subprocess.SubprocessError,
    ) as error:
        print(f"Windows guest provisioning failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
