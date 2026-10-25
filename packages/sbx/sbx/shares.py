# Copyright (c) 2026 Bad3r
"""Runtime virtiofs shares of sandboxes.

A sandbox takes its own shared directory read-write, or a directory the host
declares in `workloads.grants.sandboxShares` read-only, and nothing else.
Session hot-plug needs no root, so sbx reads the grant helper's policy file
itself instead of asking the helper.
"""

import json
import os
import re
import shlex
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, Protocol, cast

from sbx import journal
from sbx.errors import SbxError
from sbx.model import DOMAIN_PREFIX, SHARED
from sbx.results import GcAction, GuestMount, GuestUnmount, ShareResult, ShareView

if TYPE_CHECKING:
    from collections.abc import Callable, Sequence

    from sbx.model import ExecResult, Sandbox
    from sbx.sandboxes import Sandboxes

# Written by modules/workloads/sharing/grants.nix.
POLICY = Path("/etc/workloads/grants.json")
# libvirt itself waits five seconds for the guest to release a device.
DETACH_WAIT = 15.0
DETACH_POLL = 0.5
# Bounds each guest helper: the mount, findmnt, and every umount.
GUEST_TIMEOUT = 30.0
MOUNT_WAIT = 10.0
MOUNT_ROOT = "/mnt"
# findmnt --raw writes a byte outside printable ASCII, a space, or a backslash as \xHH.
RAW_ESCAPE = re.compile(rb"\\x([0-9a-fA-F]{2})")


class ShareBackend(Protocol):
    """Live devices of session domains."""

    def live_xml(self, domain: str) -> str:
        """Return the live definition."""
        ...

    def attach_device(self, domain: str, xml: str) -> None:
        """Hot-plug a device into the running domain only."""
        ...

    def detach_device(self, domain: str, xml: str) -> None:
        """Ask the running domain to release a device."""
        ...


@dataclass(frozen=True)
class Device:
    """One live virtiofs device."""

    xml: str
    source: str
    read_only: bool


def declared(policy: Path) -> dict[str, Path]:
    """Return the read-only sandbox shares the policy file names; none without the file."""
    try:
        data: object = json.loads(policy.read_text())
    except FileNotFoundError:
        return {}
    except ValueError as error:
        msg = f"{policy} holds no valid JSON: {error}"
        raise SbxError(msg, code="policy-file") from error
    try:
        entries = cast(
            "dict[str, dict[str, object]]", cast("dict[str, object]", data)["sandboxShares"]
        )
        return {name: Path(str(entry["hostPath"])) for name, entry in entries.items()}
    except (AttributeError, KeyError, TypeError) as error:
        msg = f"{policy} holds no sandboxShares table: {error!r}"
        raise SbxError(msg, code="policy-file") from error


def attached(xml: str) -> dict[str, Device]:
    """Return the live virtiofs devices of a domain definition by tag."""
    devices: dict[str, Device] = {}
    for element in ET.fromstring(xml).iterfind("devices/filesystem"):  # noqa: S314
        driver, target = element.find("driver"), element.find("target")
        if driver is None or driver.get("type") != "virtiofs" or target is None:
            continue
        source = element.find("source")
        devices[str(target.get("dir"))] = Device(
            ET.tostring(element, encoding="unicode"),
            "" if source is None else str(source.get("dir")),
            element.find("readonly") is not None,
        )
    return devices


def device_xml(virtiofsd: str, source: Path, tag: str, *, read_only: bool) -> str:
    """Render the `<filesystem>` device of one share."""
    element = ET.Element("filesystem", type="mount", accessmode="passthrough")
    ET.SubElement(element, "driver", type="virtiofs")
    ET.SubElement(element, "binary", path=virtiofsd)
    ET.SubElement(element, "source", dir=str(source))
    ET.SubElement(element, "target", dir=tag)
    # Only the owner's ids in virtiofsd's namespace, so libvirt skips its /etc/subuid map;
    # the sbx-virtiofsd wrapper squashes every guest id onto them.
    idmap = ET.SubElement(element, "idmap")
    ET.SubElement(idmap, "uid", start="0", target=str(os.geteuid()), count="1")
    ET.SubElement(idmap, "gid", start="0", target=str(os.getegid()), count="1")
    if read_only:
        ET.SubElement(element, "readonly")
    return ET.tostring(element, encoding="unicode")


def mountpoint(tag: str) -> str:
    """Return the guest directory `share attach` mounts a tag on."""
    return f"{MOUNT_ROOT}/{tag}"


def mount_command(tag: str, *, read_only: bool) -> str:
    """Return the guest shell command that mounts a tag on its mountpoint."""
    target = shlex.quote(mountpoint(tag))
    options = " -o ro" if read_only else ""
    return f"mkdir -p {target} && mount -t virtiofs{options} {shlex.quote(tag)} {target}"


def find_command(tag: str) -> list[str]:
    """Return the guest argv that lists every mountpoint of a tag, one per line."""
    return ["findmnt", "-t", "virtiofs", "-S", tag, "-o", "TARGET", "-n", "-r"]


def recovery_command(name: str, tag: str) -> str:
    """Return the host command that lazily unmounts what a detach left in the guest."""
    script = f"{shlex.join(find_command(tag))} | xargs -r umount -l"
    return shlex.join(["sbx", "exec", name, "--", "sh", "-c", script])


def _unescape(field: bytes) -> str:
    return RAW_ESCAPE.sub(lambda match: bytes([int(match[1], 16)]), field).decode(errors="replace")


def _detail(result: ExecResult) -> str:
    text = result.stderr.decode(errors="replace").strip()
    return "".join(c if c.isprintable() else " " for c in text)[:300] or "no message"


def _failure(result: ExecResult) -> str | None:
    """Why a guest helper failed, or None when it exited 0."""
    if result.transport_error is not None:
        return result.transport_error
    if result.timed_out:
        return f"it did not finish in {GUEST_TIMEOUT:g} s"
    if result.exit_code != 0:
        return f"it exited {result.status()}: {_detail(result)}"
    return None


class Shares:
    """`sbx share attach` and `detach`."""

    def __init__(
        self,
        sandboxes: Sandboxes,
        policy: Path = POLICY,
        *,
        sleep: Callable[[float], None] = time.sleep,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        """Bind the sandboxes and the policy file."""
        self.sandboxes = sandboxes
        self.policy = policy
        self.sleep = sleep
        self.clock = clock

    def _backend(self) -> ShareBackend:
        return cast("ShareBackend", self.sandboxes.backend())

    def _source(self, name: str, tag: str) -> tuple[Path, bool]:
        """The resolved host directory of a share and whether it is read-only."""
        if tag == SHARED:
            try:
                shared = self.sandboxes.paths.sandbox(name).resolve(strict=True) / SHARED
                shared.mkdir(mode=0o700, exist_ok=True)
            except OSError as error:
                msg = f"the {SHARED} directory of {name} is unusable: {error}"
                raise SbxError(msg, code="path-denied") from error
            if shared.is_symlink() or not shared.is_dir():
                msg = f"{shared} is no directory"
                raise SbxError(msg, code="path-denied")
            return shared, False
        shares = declared(self.policy)
        if tag not in shares:
            msg = (
                f"'{tag}' is neither {SHARED} nor a workloads.grants.sandboxShares entry;"
                " a sandbox gets no other host directory"
            )
            raise SbxError(msg, code="not-declared")
        try:
            path = shares[tag].resolve(strict=True)
        except OSError as error:
            msg = f"sandbox share {tag}: {shares[tag]} is unreadable: {error.strerror}"
            raise SbxError(msg, code="path-denied") from error
        home, state = Path.home().resolve(), self.sandboxes.paths.root.resolve()
        if not path.is_dir():
            msg = f"sandbox share {tag}: {path} is no directory"
            raise SbxError(msg, code="path-denied")
        if home.is_relative_to(path) or state.is_relative_to(path) or path.is_relative_to(state):
            msg = f"sandbox share {tag}: {path} would expose $HOME or the sbx state directory"
            raise SbxError(msg, code="path-denied")
        return path, True

    def attach(self, name: str, tag: str, *, mount: bool = True) -> ShareResult:
        """Hot-plug a share into a running sandbox; it stays until detached or stopped.

        With `mount`, the guest then mounts it on its mountpoint; a failed mount
        leaves the share attached and says why.
        """
        with self.sandboxes.locked():
            sandbox = self.sandboxes.running(name)
            if self.sandboxes.windows_base(sandbox.meta.base) is not None:
                # As for system guests: virtiofs.exe needs a provisioning flow to mount.
                msg = f"sandbox '{name}' runs Windows, which takes no runtime share"
                raise SbxError(msg, code="unsupported-guest")
            domain = sandbox.domain.name
            source, read_only = self._source(name, tag)
            if not read_only:
                self.sandboxes.check_disk()
            backend = self._backend()
            if tag in attached(backend.live_xml(domain)):
                msg = f"sandbox '{name}' already holds {tag}"
                raise SbxError(msg, code="already-attached")
            journal.record(
                f"share {tag} attached to {name}",
                verb="share",
                sandbox=name,
                share=tag,
                read_only=read_only,
                session=self.sandboxes.session,
            )
            virtiofsd = self.sandboxes.settings.tools.virtiofsd
            backend.attach_device(domain, device_xml(virtiofsd, source, tag, read_only=read_only))
        command = mount_command(tag, read_only=read_only)
        error = self._mount(sandbox, tag, command) if mount else None
        guest = GuestMount(
            mountpoint(tag),
            mounted=mount and error is None,
            mount_command=command,
            unmount_command=shlex.join(["umount", mountpoint(tag)]),
            error=error,
        )
        return ShareResult(
            name, tag, read_only=read_only, host_path=str(source), attached=True, guest=guest
        )

    def _mount(self, sandbox: Sandbox, tag: str, command: str) -> str | None:
        """Mount an attached share in the guest; return why that failed, or None.

        The guest probes the hot-plugged device after attach returns, so a mount
        that fails is retried until MOUNT_WAIT passes.
        """
        deadline = self.clock() + MOUNT_WAIT
        while True:
            result = self._helper(sandbox, ["sh", "-c", command])
            if isinstance(result, str):
                failure: str | None = result
                break
            failure = _failure(result)
            if failure is None or self.clock() >= deadline:
                break
            self.sleep(DETACH_POLL)
        if failure is not None:
            failure = f"the guest did not mount {tag}: {failure}"
            journal.record(failure, verb="share", sandbox=sandbox.name, share=tag)
        return failure

    def detach(self, name: str, tag: str, *, force: bool = False) -> ShareResult:
        """Unmount a share in the guest, then remove it and wait until the guest releases it.

        A busy mount refuses unless `force` unmounts it lazily; a guest that does
        not answer leaves its mounts, and the result says how to clear them.
        """
        with self.sandboxes.locked():
            sandbox = self.sandboxes.find(name)
            if sandbox.domain.managed_save:
                msg = f"sandbox '{name}' is saved with its shares; restore it, then detach"
                raise SbxError(msg, code="saved")
            backend = self._backend()
            held = attached(backend.live_xml(sandbox.domain.name)) if sandbox.domain.active else {}
            if tag not in held:
                msg = f"sandbox '{name}' holds no {tag}"
                raise SbxError(msg, code="not-attached")
            device = held[tag]
            guest = self._unmount(sandbox, tag, force=force)
            self._detach(name, tag, device)
        return ShareResult(
            name,
            tag,
            read_only=device.read_only,
            host_path=device.source,
            attached=False,
            guest=guest,
        )

    def _helper(self, sandbox: Sandbox, command: Sequence[str]) -> ExecResult | str:
        """Run a guest helper; return its result, or why the guest did not answer sanely."""
        try:
            result = self.sandboxes.guest_helper(sandbox, command, timeout=GUEST_TIMEOUT)
        except SbxError as error:
            # Malformed replies come from the guest, which must not keep a share by sending one.
            return f"qemu-ga: {error}"
        if result.transport_error is not None:
            return result.transport_error
        if result.timed_out:
            return f"{command[0]} did not finish in {GUEST_TIMEOUT:g} s"
        return result

    def _unmount(self, sandbox: Sandbox, tag: str, *, force: bool) -> GuestUnmount:
        """Unmount every guest mount of a tag, topmost first; lazily with `force`."""
        name = sandbox.name
        unmounted: list[str] = []

        def abandon(reason: str) -> GuestUnmount:
            journal.record(
                f"share {tag} of {name} stays mounted in the guest: {reason}",
                verb="share",
                sandbox=name,
                share=tag,
            )
            return GuestUnmount(tuple(unmounted), recovery_command(name, tag))

        found = self._helper(sandbox, find_command(tag))
        if isinstance(found, str):
            return abandon(found)
        # findmnt exits 1 when nothing matches.
        if found.exit_code not in {0, 1}:
            reason = f"findmnt exited {found.status()}: {_detail(found)}"
            if not force:
                msg = f"cannot list the mounts of {tag} in {name}: {reason}"
                raise SbxError(msg, code="guest-command")
            return abandon(reason)
        targets = [_unescape(line) for line in found.stdout.splitlines() if line]
        for target in reversed(targets):
            result = self._helper(
                sandbox, ["umount", "-l", target] if force else ["umount", target]
            )
            if isinstance(result, str):
                return abandon(result)
            if result.exit_code != 0:
                detail = _detail(result)
                reason = f"umount {target} exited {result.status()}: {detail}"
                if force:
                    return abandon(reason)
                if "busy" in detail:
                    msg = (
                        f"{target} in {name} is busy: {reason}; stop what uses it, or detach"
                        " with --force to unmount it lazily"
                    )
                    raise SbxError(msg, code="share-busy")
                raise SbxError(reason, code="guest-command")
            unmounted.append(target)
        return GuestUnmount(tuple(unmounted))

    def views(self, sandbox: Sandbox) -> tuple[ShareView, ...]:
        """Describe the shares a running sandbox holds, with each one's first guest mountpoint."""
        if not sandbox.domain.active:
            return ()
        held = attached(self._backend().live_xml(sandbox.domain.name))
        if not held:
            return ()
        mounts = self._mounts(sandbox)
        return tuple(
            ShareView(tag, device.read_only, device.source, mounts.get(tag))
            for tag, device in held.items()
        )

    def _mounts(self, sandbox: Sandbox) -> dict[str, str]:
        """Map each mounted virtiofs tag to its first mountpoint; empty when the guest is silent."""
        command = ["findmnt", "-t", "virtiofs", "-o", "SOURCE,TARGET", "-n", "-r"]
        found = self._helper(sandbox, command)
        if isinstance(found, str) or found.exit_code not in {0, 1}:
            reason = found if isinstance(found, str) else f"findmnt exited {found.status()}"
            journal.record(f"no guest mounts for {sandbox.name}: {reason}", sandbox=sandbox.name)
            return {}
        mounts: dict[str, str] = {}
        for line in found.stdout.splitlines():
            source, _, target = line.partition(b" ")
            if target:
                mounts.setdefault(_unescape(source), _unescape(target))
        return mounts

    def _detach(self, name: str, tag: str, device: Device, reason: str = "") -> None:
        """Detach under the caller's lock and wait until the device leaves."""
        domain = DOMAIN_PREFIX + name
        backend = self._backend()
        journal.record(
            f"share {tag} detached from {name}{reason}",
            verb="share",
            sandbox=name,
            share=tag,
            session=self.sandboxes.session,
        )
        backend.detach_device(domain, device.xml)
        deadline = self.clock() + DETACH_WAIT
        while tag in attached(backend.live_xml(domain)):
            if self.clock() >= deadline:
                msg = (
                    f"sandbox '{name}' still holds {tag} {DETACH_WAIT:g}s after the detach"
                    f" request; the share stays usable until the guest releases it, and"
                    f" `sbx destroy {name}` ends it"
                )
                raise SbxError(msg, code="detach-pending")
            self.sleep(DETACH_POLL)

    def _shared_device(self, domain: str) -> Device | None:
        try:
            live = self._backend().live_xml(domain)
        except SbxError as error:
            if error.code != "not-found":
                raise
            return None
        return attached(live).get(SHARED)

    def reclaim(self, *, dry_run: bool) -> list[GcAction]:
        """Detach every sandbox's shared directory while usage passes the cap or the floor."""
        if not self.sandboxes.has_state():
            return []
        actions: list[GcAction] = []
        with self.sandboxes.locked():
            problem = self.sandboxes.disk_problem()
            if problem is None:
                return []
            for sandbox in self.sandboxes.owned():
                if not sandbox.domain.active:
                    continue
                device = self._shared_device(sandbox.domain.name)
                if device is None:
                    continue
                reason = f"{SHARED} detached: {problem}"
                if not dry_run:
                    try:
                        self._detach(sandbox.name, SHARED, device, f": {problem}")
                    except SbxError as error:
                        if error.code == "not-found":
                            continue
                        if error.code != "detach-pending":
                            raise
                        reason = f"{SHARED} still attached, {error.code}: {error}"
                actions.append(GcAction(sandbox.name, reason))
        return actions
