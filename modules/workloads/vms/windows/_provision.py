# Copyright (c) 2026 Bad3r
"""Provision one declared Windows guest through its QEMU guest agent.

The unit runs from the guest's start until it stops. It waits for the guest
agent and for firstlogon.ps1, then runs each step: a step probes the guest and
applies only what differs, so every start converges without repeating work.
"""

import argparse
import base64
import json
import sys
import threading
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING

import libvirt
import libvirt_qemu

if TYPE_CHECKING:
    from collections.abc import Callable

AGENT_CHANNEL = "org.qemu.guest_agent.0"
POWERSHELL = r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
STATE_DIR = r"C:\ProgramData\workloads"
AUTHORIZED_KEYS = r"C:\ProgramData\ssh\administrators_authorized_keys"
# Step scripts exit with this code when a probe finds the guest differs.
DIFFERS = 10
# Linux keycode of Enter, which answers "Press any key to boot from CD or DVD".
KEY_ENTER = 28
# An OS disk with less data than this holds no installed system yet.
FRESH_DISK = 1 << 30
BOOT_KEY_SECONDS = 30
FIRSTLOGON_TIMEOUT = 2 * 60 * 60
# The agent arrives with the guest tools, at the end of an installation.
INSTALL_AGENT_TIMEOUT = 3 * 60 * 60
AGENT_CONNECT_TIMEOUT = 30 * 60
POLL_SECONDS = 15
EXEC_TIMEOUT = 15 * 60
AGENT_TIMEOUT = 60
CHUNK = 48 * 1024


class ProvisionError(Exception):
    """The guest cannot be brought to its declared state."""


def log(message: str) -> None:
    """Print one journal line."""
    print(message, flush=True)


@dataclass(frozen=True)
class Result:
    """Outcome of one guest-exec run."""

    code: int
    stdout: str
    stderr: str


class Agent:
    """Commands for one domain's QEMU guest agent."""

    def __init__(self, domain: libvirt.virDomain) -> None:
        """Bind to a running domain."""
        self.domain = domain

    def call(self, command: str, **arguments: object) -> object:
        """Run one agent command and return its result."""
        request: dict[str, object] = {"execute": command}
        if arguments:
            request["arguments"] = arguments
        reply = libvirt_qemu.qemuAgentCommand(self.domain, json.dumps(request), AGENT_TIMEOUT, 0)
        return json.loads(reply)["return"]

    def run(self, path: str, args: list[str], stdin: bytes) -> Result:
        """Run a guest program to completion and capture its output."""
        started = self.call(
            "guest-exec",
            path=path,
            arg=args,
            **{"input-data": base64.b64encode(stdin).decode(), "capture-output": True},
        )
        pid = started["pid"]  # type: ignore[index]
        deadline = time.monotonic() + EXEC_TIMEOUT
        while True:
            status = self.call("guest-exec-status", pid=pid)
            if status["exited"]:  # type: ignore[index]
                break
            if time.monotonic() > deadline:
                msg = f"{path} ran longer than {EXEC_TIMEOUT} s"
                raise ProvisionError(msg)
            time.sleep(1)

        def decode(key: str) -> str:
            return base64.b64decode(status.get(key, "")).decode(errors="replace")  # type: ignore[union-attr]

        return Result(status.get("exitcode", -1), decode("out-data"), decode("err-data"))  # type: ignore[union-attr]

    def read(self, path: str) -> bytes:
        """Return the content of a guest file."""
        handle = self.call("guest-file-open", path=path, mode="rb")
        data = b""
        try:
            while True:
                chunk = self.call("guest-file-read", handle=handle, count=CHUNK)
                data += base64.b64decode(chunk["buf-b64"])  # type: ignore[index]
                if chunk["eof"]:  # type: ignore[index]
                    return data
        finally:
            self.call("guest-file-close", handle=handle)

    def write(self, path: str, data: bytes) -> None:
        """Replace the content of a guest file."""
        handle = self.call("guest-file-open", path=path, mode="wb")
        try:
            for offset in range(0, len(data), CHUNK):
                piece = data[offset : offset + CHUNK]
                self.call(
                    "guest-file-write",
                    handle=handle,
                    **{"buf-b64": base64.b64encode(piece).decode()},
                )
            self.call("guest-file-flush", handle=handle)
        finally:
            self.call("guest-file-close", handle=handle)


@dataclass
class Guest:
    """A running guest, its declaration, and its step scripts."""

    agent: Agent
    spec: dict
    scripts: Path

    def script(self, name: str, mode: str, data: dict) -> Result:
        """Run a step script with its input on stdin, never in an argument."""
        source = f"$ErrorActionPreference = 'Stop'\n$Mode = '{mode}'\n"
        source += "$Data = [Console]::In.ReadToEnd() | ConvertFrom-Json\n"
        source += (self.scripts / f"{name}.ps1").read_text()
        encoded = base64.b64encode(source.encode("utf-16-le")).decode()
        args = [
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-EncodedCommand",
            encoded,
        ]
        return self.agent.run(POWERSHELL, args, json.dumps(data).encode())

    def probe(self, name: str, data: dict) -> bool:
        """Return whether a step script finds the guest as declared."""
        result = self.script(name, "probe", data)
        if result.code not in {0, DIFFERS}:
            msg = f"{name} probe exited with {result.code}: {result.stderr.strip()}"
            raise ProvisionError(msg)
        return result.code == 0

    def apply(self, name: str, data: dict) -> None:
        """Bring the guest in line with a step script."""
        result = self.script(name, "apply", data)
        if result.code != 0:
            msg = f"{name} exited with {result.code}: {result.stderr.strip()}"
            raise ProvisionError(msg)

    def exists(self, path: str) -> bool:
        """Return whether a guest path exists."""
        return self.probe("exists", {"path": path})


@dataclass(frozen=True)
class Step:
    """One idempotent provisioning step; a step without a probe always applies."""

    name: str
    probe: Callable[[Guest], bool] | None
    apply: Callable[[Guest], None]


def read_secret(path: str) -> str:
    """Read a sops-nix secret file without its trailing newline."""
    return Path(path).read_text().rstrip("\r\n")


def set_password(guest: Guest) -> None:
    """Set the account password through libvirt, so it never appears in an argument."""
    account = guest.spec["account"]
    guest.agent.domain.setUserPassword(account, read_secret(guest.spec["passwordFile"]), 0)


def product_key_data(guest: Guest) -> dict:
    """Return the product key as step input."""
    return {"key": read_secret(guest.spec["productKeyFile"])}


def authorized_keys_content(guest: Guest) -> bytes:
    """Return the declared administrators_authorized_keys file."""
    return "".join(f"{key}\n" for key in guest.spec["authorizedKeys"]).encode()


def authorized_keys_in_place(guest: Guest) -> bool:
    """Compare the guest's key file and its ACL with the declaration."""
    if not guest.probe("authorized-keys", {"path": AUTHORIZED_KEYS}):
        return False
    return guest.agent.read(AUTHORIZED_KEYS) == authorized_keys_content(guest)


def write_authorized_keys(guest: Guest) -> None:
    """Write the key file, then restrict it to SYSTEM and Administrators as sshd requires."""
    guest.agent.write(AUTHORIZED_KEYS, authorized_keys_content(guest))
    guest.apply("authorized-keys", {"path": AUTHORIZED_KEYS})


def script_step(name: str, data: Callable[[Guest], dict]) -> Step:
    """Build a step whose probe and apply are one script's two modes."""
    return Step(
        name,
        lambda guest: guest.probe(name, data(guest)),
        lambda guest: guest.apply(name, data(guest)),
    )


def steps(spec: dict) -> list[Step]:
    """Return the steps a declaration asks for, in order."""
    result = [
        Step("password", None, set_password),
        Step("authorized-keys", authorized_keys_in_place, write_authorized_keys),
        script_step("remote-desktop", lambda guest: {"remote": guest.spec["gateways"]}),
        script_step("firewall", lambda guest: {"rules": guest.spec["services"]}),
    ]
    # Last: activation depends on Microsoft's servers and the key, so a failure
    # there leaves access to the guest in place.
    key_file = spec["productKeyFile"]
    if key_file is not None and Path(key_file).is_file():
        result.append(script_step("product-key", product_key_data))
    else:
        log("no product key file; Windows stays unactivated")
    return result


def converge(guest: Guest, plan: list[Step]) -> None:
    """Probe each step and apply the ones that differ."""
    for step in plan:
        if step.probe is not None and step.probe(guest):
            log(f"{step.name}: in place")
            continue
        step.apply(guest)
        if step.probe is not None and not step.probe(guest):
            msg = f"{step.name}: the guest still differs after the step applied"
            raise ProvisionError(msg)
        log(f"{step.name}: applied")


def agent_connected(domain: libvirt.virDomain) -> bool:
    """Return whether the live definition reports a connected guest agent."""
    root = ET.fromstring(domain.XMLDesc(0))  # noqa: S314
    for target in root.iterfind("devices/channel/target"):
        if target.get("name") == AGENT_CHANNEL:
            return target.get("state") == "connected"
    msg = "the guest has no guest agent channel"
    raise ProvisionError(msg)


def press_boot_key(domain: libvirt.virDomain, disk: str) -> None:
    """Answer the installer's boot prompt while the OS disk is still empty."""
    allocation = domain.blockInfo(disk)[1]
    if allocation >= FRESH_DISK:
        return
    log("the OS disk is empty; pressing Enter for the installer's boot prompt")
    deadline = time.monotonic() + BOOT_KEY_SECONDS
    while time.monotonic() < deadline:
        domain.sendKey(libvirt.VIR_KEYCODE_SET_LINUX, 0, [KEY_ENTER], 1, 0)
        time.sleep(1)


def wait_for_agent(conn: libvirt.virConnect, domain: libvirt.virDomain, deadline: float) -> None:
    """Block until the guest agent connects, failing at the deadline."""
    connected = threading.Event()

    def on_lifecycle(
        _conn: object, _domain: object, state: int, _reason: int, _opaque: object
    ) -> None:
        if state == libvirt.VIR_CONNECT_DOMAIN_EVENT_AGENT_LIFECYCLE_STATE_CONNECTED:
            connected.set()

    callback = conn.domainEventRegisterAny(
        domain, libvirt.VIR_DOMAIN_EVENT_ID_AGENT_LIFECYCLE, on_lifecycle, None
    )
    try:
        announced = False
        while not agent_connected(domain):
            if time.monotonic() > deadline:
                msg = (
                    "the guest agent did not connect in time; check on the console that the "
                    "guest booted and the QEMU Guest Agent service runs, then restart this unit"
                )
                raise ProvisionError(msg)
            if not announced:
                log("waiting for the guest agent")
                announced = True
            connected.wait(POLL_SECONDS)
            connected.clear()
    finally:
        conn.domainEventDeregisterAny(callback)
    log("the guest agent is connected")


def wait_for_firstlogon(conn: libvirt.virConnect, guest: Guest) -> None:
    """Block until firstlogon.ps1 finishes; fail with its error if it failed."""
    deadline = time.monotonic() + FIRSTLOGON_TIMEOUT
    announced = False
    while True:
        failed = False
        try:
            if guest.exists(rf"{STATE_DIR}\firstlogon.done"):
                return
            failed = guest.exists(rf"{STATE_DIR}\firstlogon.failed")
        except libvirt.libvirtError as error:
            # Installers restart the agent while firstlogon.ps1 runs.
            log(f"the guest agent dropped a command ({error}); waiting for it again")
            wait_for_agent(conn, guest.agent.domain, deadline)
        except ProvisionError as error:
            # PowerShell fails to start while the guest tools replace drivers.
            log(f"probing for firstlogon.ps1 failed ({error}); retrying")
        if failed:
            error = guest.agent.read(rf"{STATE_DIR}\firstlogon.failed").decode(errors="replace")
            msg = f"firstlogon.ps1 failed: {error.strip()}"
            raise ProvisionError(msg)
        if time.monotonic() > deadline:
            msg = (
                f"firstlogon.ps1 did not finish within {FIRSTLOGON_TIMEOUT // 60} minutes; "
                "a guest shut down while it ran never finishes it, so run it again by hand "
                "as the Windows guests page describes, then restart this unit"
            )
            raise ProvisionError(msg)
        if not announced:
            log("waiting for firstlogon.ps1")
            announced = True
        time.sleep(POLL_SECONDS)


def provision(conn: libvirt.virConnect, spec: dict, scripts: Path) -> None:
    """Provision one guest from the moment it starts."""
    domain = conn.lookupByUUIDString(spec["uuid"])
    if not domain.isActive():
        msg = f"guest '{domain.name()}' is not running; its next start provisions it"
        raise ProvisionError(msg)
    if spec["install"]:
        press_boot_key(domain, spec["osDisk"])
    timeout = INSTALL_AGENT_TIMEOUT if spec["install"] else AGENT_CONNECT_TIMEOUT
    wait_for_agent(conn, domain, time.monotonic() + timeout)
    guest = Guest(Agent(domain), spec, scripts)
    wait_for_firstlogon(conn, guest)
    converge(guest, steps(spec))
    log(f"guest '{domain.name()}' is provisioned")


def run_event_loop() -> None:
    """Dispatch libvirt events for the lifetime of the process."""
    while True:
        libvirt.virEventRunDefaultImpl()


def main() -> int:
    """Provision the guest a manifest entry names."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("name")
    parser.add_argument("--scripts", type=Path, required=True, help="directory of step scripts")
    parser.add_argument("--connect", default="qemu:///system")
    args = parser.parse_args()

    guests = json.loads(args.manifest.read_text())
    if args.name not in guests:
        print(f"<3>error: no declared Windows guest is named '{args.name}'", file=sys.stderr)
        return 1

    libvirt.virEventRegisterDefaultImpl()
    threading.Thread(target=run_event_loop, daemon=True).start()
    libvirt.registerErrorHandler(lambda _ctx, _error: None, None)
    try:
        conn = libvirt.open(args.connect)
        try:
            provision(conn, guests[args.name], args.scripts)
        finally:
            conn.close()
    except (ProvisionError, libvirt.libvirtError, OSError) as error:
        print(f"<3>error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
