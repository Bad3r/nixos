# Copyright (c) 2026 Bad3r
"""Define-only reconciler for declared workload objects.

`network` defines one rendered network and never destroys or restarts it.
`guest` defines or undefines one guest and never destroys, restarts, or deletes its data.
`orphans` warns about owned objects that nothing declares.
`media` stages declared media files and prunes the ones no longer declared.
`read-source` streams one source file for `media`, run with the owner's credentials.
`golden` copies a shut-off guest's files to its golden directory.
"""

import argparse
import contextlib
import hashlib
import json
import os
import pwd
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import BinaryIO

import libvirt

NAMESPACE = "https://github.com/Bad3r/nixos/workloads"
MARKER = f"{{{NAMESPACE}}}managed"
GIB = 1 << 30
# The gateway of the network libvirtd-config copies from the package.
STOCK_DEFAULT_GATEWAY = "192.168.122.1"
CHUNK = 1 << 20
# Size and modification time of the opened source, ahead of its content.
HEADER = struct.Struct(">QQ")
STAGED_MODE = 0o644
# Network sections a running network takes without a restart: parent path, key, label.
LIVE_SECTIONS = (
    (libvirt.VIR_NETWORK_SECTION_IP_DHCP_HOST, "ip/dhcp", "mac", "DHCP reservation"),
    (libvirt.VIR_NETWORK_SECTION_DNS_HOST, "dns", "ip", "DNS host"),
)


class ReconcileError(Exception):
    """A declaration conflicts with the host's current state."""


def log(message: str) -> None:
    """Print one journal line."""
    print(message, flush=True)


def warn(message: str) -> None:
    """Print one journal line at warning priority."""
    print(f"<4>{message}", flush=True)


def parse(xml: str) -> ET.Element:
    """Parse XML that libvirt or the Nix renderer produced."""
    return ET.fromstring(xml)  # noqa: S314


def is_marked(root: ET.Element) -> bool:
    """Return whether an object carries the workloads ownership marker."""
    return root.find(f"metadata/{MARKER}") is not None


def canonical(root: ET.Element) -> str:
    """Serialize a network definition without its runtime-only attributes."""
    root.attrib.pop("connections", None)
    # Live updates append records, so their order carries no meaning.
    for _, parent, key, _ in LIVE_SECTIONS:
        for element in root.iterfind(parent):
            hosts = element.findall("host")
            for host in hosts:
                element.remove(host)
            element.extend(sorted(hosts, key=lambda host, key=key: host.get(key, "")))
    return ET.canonicalize(ET.tostring(root, encoding="unicode"), strip_text=True)


def lookup_network(
    conn: libvirt.virConnect, *, uuid: str | None = None, name: str | None = None
) -> libvirt.virNetwork | None:
    """Find a network by UUID or name, or return None."""
    try:
        if uuid is not None:
            return conn.networkLookupByUUIDString(uuid)
        return conn.networkLookupByName(name)
    except libvirt.libvirtError as error:
        if error.get_error_code() == libvirt.VIR_ERR_NO_NETWORK:
            return None
        raise


def inactive_xml(network: libvirt.virNetwork) -> ET.Element:
    """Return the persistent definition of a network."""
    return parse(network.XMLDesc(libvirt.VIR_NETWORK_XML_INACTIVE))


def is_stock_default(network: libvirt.virNetwork) -> bool:
    """Return whether a network is libvirt's inactive stock `default`."""
    addresses = {ip.get("address") for ip in inactive_xml(network).findall("ip")}
    return (
        network.name() == "default"
        and not network.isActive()
        and STOCK_DEFAULT_GATEWAY in addresses
    )


def clear_way(conn: libvirt.virConnect, name: str, uuid: str) -> None:
    """Refuse to define over objects the engine does not own.

    The one exception is libvirt's inactive stock `default`, which is
    undefined so the declared network can take its name.
    """
    network = lookup_network(conn, uuid=uuid)
    if network is not None:
        current = network.name()
        if not is_marked(inactive_xml(network)):
            msg = (
                f"network {uuid} exists as '{current}' without the ownership marker; "
                "the engine never takes over objects it did not create"
            )
            raise ReconcileError(msg)
        if current != name:
            msg = (
                f"network {uuid} is defined as '{current}' and libvirt cannot rename networks; "
                f"stop its guests, run `virsh net-destroy {current}` and "
                f"`virsh net-undefine {current}`, then restart this unit"
            )
            raise ReconcileError(msg)
        return

    network = lookup_network(conn, name=name)
    if network is None:
        return
    if is_marked(inactive_xml(network)):
        msg = f"network '{name}' is defined with UUID {network.UUIDString()}, declared {uuid}"
        raise ReconcileError(msg)
    if not is_stock_default(network):
        msg = (
            f"network '{name}' exists without the ownership marker and is not libvirt's "
            "inactive stock default; rename or undefine it by hand"
        )
        raise ReconcileError(msg)
    network.undefine()
    log(f"undefined libvirt's stock '{name}' network")


def live_records(root: ET.Element, parent: str, key: str) -> dict[str, str]:
    """Map each `host` record under `parent` to its canonical XML by its key attribute."""
    return {
        host.get(key, ""): ET.canonicalize(ET.tostring(host, encoding="unicode"), strip_text=True)
        for host in root.iterfind(f"{parent}/host")
    }


def sync_live_records(network: libvirt.virNetwork, desired: ET.Element) -> None:
    """Bring the live DHCP reservations and DNS hosts of a running network in line."""
    current = parse(network.XMLDesc(0))
    flags = libvirt.VIR_NETWORK_UPDATE_AFFECT_LIVE
    for section, parent, key, label in LIVE_SECTIONS:
        live = live_records(current, parent, key)
        wanted = live_records(desired, parent, key)
        for record_key, host in live.items():
            if wanted.get(record_key) != host:
                network.update(libvirt.VIR_NETWORK_UPDATE_COMMAND_DELETE, section, -1, host, flags)
                log(f"dropped the live {label} {host}")
        for record_key, host in wanted.items():
            if live.get(record_key) != host:
                network.update(
                    libvirt.VIR_NETWORK_UPDATE_COMMAND_ADD_LAST, section, -1, host, flags
                )
                log(f"added the live {label} {host}")


def reconcile_network(conn: libvirt.virConnect, xml: str, *, autostart: bool, start: bool) -> None:
    """Define a declared network; start it when it is inactive and autostarts or `start` is set."""
    desired = parse(xml)
    name = desired.findtext("name", "")
    uuid = desired.findtext("uuid", "")
    clear_way(conn, name, uuid)
    network = conn.networkDefineXML(xml)
    log(f"defined network '{name}' ({uuid})")

    if bool(network.autostart()) != autostart:
        network.setAutostart(int(autostart))
        log(f"set autostart of network '{name}' to {autostart}")

    if network.isActive():
        sync_live_records(network, desired)
        live = canonical(parse(network.XMLDesc(0)))
        if live != canonical(inactive_xml(network)):
            log(
                f"network '{name}' runs an older definition until it restarts; "
                f"`virsh net-destroy {name} && virsh net-start {name}` applies it "
                "and drops the link of every attached guest"
            )
    elif autostart or start:
        network.create()
        log(f"started network '{name}'")


def lookup_domain(
    conn: libvirt.virConnect, *, uuid: str | None = None, name: str | None = None
) -> libvirt.virDomain | None:
    """Find a domain by UUID or name, or return None."""
    try:
        if uuid is not None:
            return conn.lookupByUUIDString(uuid)
        return conn.lookupByName(name)
    except libvirt.libvirtError as error:
        if error.get_error_code() == libvirt.VIR_ERR_NO_DOMAIN:
            return None
        raise


def domain_marker(domain: libvirt.virDomain, flags: int) -> ET.Element | None:
    """Return a domain's ownership marker without reading the rest of its definition."""
    try:
        return parse(domain.metadata(libvirt.VIR_DOMAIN_METADATA_ELEMENT, NAMESPACE, flags))
    except libvirt.libvirtError as error:
        if error.get_error_code() == libvirt.VIR_ERR_NO_DOMAIN_METADATA:
            return None
        raise


def network_marked(network: libvirt.virNetwork) -> bool:
    """Return whether a network carries the marker, without reading the rest of it."""
    try:
        network.metadata(libvirt.VIR_NETWORK_METADATA_ELEMENT, NAMESPACE, 0)
    except libvirt.libvirtError as error:
        if error.get_error_code() == libvirt.VIR_ERR_NO_NETWORK_METADATA:
            return False
        raise
    return True


def owned_domain(conn: libvirt.virConnect, uuid: str) -> libvirt.virDomain | None:
    """Find a domain by UUID and refuse one the engine did not create."""
    domain = lookup_domain(conn, uuid=uuid)
    if domain is not None and domain_marker(domain, libvirt.VIR_DOMAIN_AFFECT_CONFIG) is None:
        msg = (
            f"domain {uuid} exists as '{domain.name()}' without the ownership marker; "
            "the engine never takes over objects it did not create"
        )
        raise ReconcileError(msg)
    return domain


def claim_domain(conn: libvirt.virConnect, name: str, uuid: str) -> libvirt.virDomain | None:
    """Return the owned domain with this UUID under the declared name, or None."""
    domain = owned_domain(conn, uuid)
    holder = lookup_domain(conn, name=name)
    if holder is not None and holder.UUIDString() != uuid:
        msg = f"domain '{name}' is defined with UUID {holder.UUIDString()}, declared {uuid}"
        raise ReconcileError(msg)
    if domain is None or domain.name() == name:
        return domain

    current = domain.name()
    if domain.isActive():
        msg = f"domain {uuid} runs as '{current}'; shut it down so it can be renamed to '{name}'"
        raise ReconcileError(msg)
    domain.rename(name, 0)
    log(f"renamed domain '{current}' to '{name}'")
    return domain


def qemu_img(*args: str) -> str:
    """Run qemu-img and return its output."""
    return subprocess.run(["qemu-img", *args], check=True, capture_output=True, text=True).stdout


def virtual_size(path: Path) -> int:
    """Return the virtual size of a disk image, which may be open in a running guest."""
    return json.loads(qemu_img("info", "-U", "-f", "qcow2", "--output=json", str(path)))[
        "virtual-size"
    ]


def check_size(path: Path, size: int) -> None:
    """Fail when an image is larger than declared; note when it is smaller."""
    actual = virtual_size(path)
    if actual > size * GIB:
        msg = f"{path} has {actual / GIB:g} GiB, declared {size} GiB; disks never shrink"
        raise ReconcileError(msg)
    if actual < size * GIB:
        log(
            f"{path} has {actual / GIB:g} GiB, declared {size} GiB; "
            f"grow it with `qemu-img resize {path} {size}G` while the guest is shut off"
        )


def seed_problem(seed: dict[str, str]) -> str | None:
    """Describe why a seed's out-link cannot seed a disk, or return None when it can."""
    out_link = Path(seed["outLink"])
    if not os.path.lexists(out_link):
        return f"the out-link {out_link} is missing"
    resolved = Path(seed["path"]).resolve()
    if str(resolved) != seed["expected"] or not resolved.is_file():
        return (
            f"the out-link {out_link} is stale: "
            f"it points at {resolved}, declared {seed['expected']}"
        )
    return None


def seed_fix(problem: str, seed: dict[str, str]) -> str:
    """Append the command that rebuilds a seed's out-link to its problem."""
    return (
        f"{problem}; build it from the repository root with `{seed['build']}` "
        "(`path:.#` in a linked worktree)"
    )


def pending_seeds(disks: list[dict]) -> list[str]:
    """Describe the seeds that block creating a missing disk."""
    problems = []
    for disk in disks:
        seed = disk["seed"]
        if seed is not None and not Path(disk["path"]).exists():
            problem = seed_problem(seed)
            if problem is not None:
                problems.append(seed_fix(problem, seed))
    return list(dict.fromkeys(problems))


def pending_install(install: dict) -> list[str]:
    """Describe the staged media and images a first install still lacks."""
    problems = [
        f"the staged medium {path} is missing; put its source in place and run "
        "`sudo systemctl restart workloads-vm-media.service`"
        for path in install["media"]
        if not Path(path).is_file()
    ]
    for image in install["images"]:
        problem = seed_problem(image)
        if problem is not None:
            problems.append(seed_fix(problem, image))
    return problems


def fill_disk(partial: Path, size: int, seed: dict[str, str] | None) -> None:
    """Write an empty or seeded qcow2 image of the declared size."""
    if seed is None:
        qemu_img("create", "-q", "-f", "qcow2", str(partial), f"{size}G")
        return
    problem = seed_problem(seed)
    if problem is not None:
        raise ReconcileError(seed_fix(problem, seed))
    qemu_img("convert", "-f", "qcow2", "-O", "qcow2", seed["expected"], str(partial))
    if virtual_size(partial) > size * GIB:
        msg = f"the seed {seed['path']} is larger than the declared {size} GiB"
        raise ReconcileError(msg)
    qemu_img("resize", "-q", "-f", "qcow2", str(partial), f"{size}G")


def create_disk(path: Path, size: int, seed: dict[str, str] | None) -> None:
    """Create a disk image, empty or copied from its seed, at its declared size."""
    fd, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    os.close(fd)
    partial = Path(name)
    try:
        fill_disk(partial, size, seed)
        partial.replace(path)
    except BaseException:
        partial.unlink(missing_ok=True)
        raise
    log(f"created {path}")


def ensure_disks(disks: list[dict], *, create: bool) -> None:
    """Check every declared disk; create the missing ones only for a guest without NVRAM."""
    for disk in disks:
        path = Path(disk["path"])
        if path.exists():
            check_size(path, disk["size"])
        elif create:
            create_disk(path, disk["size"], disk["seed"])
        else:
            msg = (
                f"{path} is missing and the guest already has its NVRAM, so it is not created; "
                f"restore a lost disk from a backup, or create a new one with "
                f"`qemu-img create -f qcow2 {path} {disk['size']}G`"
            )
            raise ReconcileError(msg)


def ensure_nvram(domain: libvirt.virDomain, path: Path) -> bool:
    """Copy the firmware's variable template if NVRAM is missing; return whether it did."""
    if path.exists():
        return False
    nvram = parse(domain.XMLDesc(libvirt.VIR_DOMAIN_XML_INACTIVE)).find("os/nvram")
    template = nvram.get("template") if nvram is not None else None
    if template is None:
        msg = f"libvirt selected no NVRAM template for {path}"
        raise ReconcileError(msg)
    fd, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    partial = Path(name)
    try:
        with os.fdopen(fd, "wb") as out, Path(template).open("rb") as source:
            shutil.copyfileobj(source, out, CHUNK)
        partial.replace(path)
    except BaseException:
        partial.unlink(missing_ok=True)
        raise
    log(f"created {path} from {template}")
    return True


def revision(marker: ET.Element | None) -> str | None:
    """Return the definition digest a marker records."""
    return marker.get("revision") if marker is not None else None


def reconcile_guest(conn: libvirt.virConnect, spec: dict) -> None:
    """Define a declared guest without touching it while it runs."""
    name, uuid = spec["name"], spec["uuid"]
    xml = Path(spec["xml"]).read_text()
    nvram = Path(spec["nvram"])
    state = Path(spec["stateDir"])
    existing = claim_domain(conn, name, uuid)
    # NVRAM is the last file a first define writes and TPM state appears at the
    # first start, so either one means the guest's files are no longer new.
    provisioned = nvram.exists() or (state / "tpm").exists()
    if provisioned and not nvram.exists():
        msg = f"{nvram} is missing although the guest has TPM state; restore it from a backup"
        raise ReconcileError(msg)
    # Images and media are built or fetched by hand, and images change with
    # every input bump, so a new guest waits for them instead of failing the switch.
    pending = [] if provisioned else pending_seeds(spec["disks"]) + pending_install(spec["install"])
    if pending:
        steps = (
            f"{'; '.join(pending)}; then `sudo systemctl restart workloads-vm-guest-{name}.service`"
        )
        if existing is not None:
            msg = (
                f"guest '{name}' is defined, but its disk waits for files to install from: {steps}"
            )
            raise ReconcileError(msg)
        warn(f"guest '{name}' is not defined until its installation files exist: {steps}")
        return
    state.mkdir(mode=0o711, exist_ok=True)
    state.chmod(0o711)
    ensure_disks(spec["disks"], create=not provisioned)

    domain = conn.defineXML(xml)
    log(f"defined guest '{name}' ({uuid})")
    # Every guest boots UEFI, so the run that writes NVRAM finishes provisioning.
    provisioned_now = ensure_nvram(domain, nvram)

    autostart = spec["autostart"]
    if bool(domain.autostart()) != autostart:
        domain.setAutostart(int(autostart))
        log(f"set autostart of guest '{name}' to {autostart}")

    if domain.isActive():
        desired = revision(parse(xml).find(f"metadata/{MARKER}"))
        if revision(domain_marker(domain, libvirt.VIR_DOMAIN_AFFECT_LIVE)) != desired:
            log(
                f"guest '{name}' runs an older definition until its next cold boot; "
                "a reboot inside the guest keeps it, a shutdown and start applies it"
            )
    elif provisioned_now and autostart:
        domain.create()
        log(f"started guest '{name}'")


def remove_guest(conn: libvirt.virConnect, spec: dict) -> None:
    """Undefine a guest declared absent, keeping its disks, NVRAM, and TPM state."""
    uuid = spec["uuid"]
    domain = owned_domain(conn, uuid)
    if domain is None:
        return
    current = domain.name()
    if domain.isActive():
        msg = f"guest '{current}' is running; shut it down so it can be undefined"
        raise ReconcileError(msg)
    if domain.snapshotNum(0) > 0:
        msg = f"guest '{current}' has snapshots; delete them so it can be undefined"
        raise ReconcileError(msg)
    if domain.hasManagedSaveImage(0):
        msg = f"guest '{current}' has a managed save image; start and shut it down first"
        raise ReconcileError(msg)
    domain.undefineFlags(
        libvirt.VIR_DOMAIN_UNDEFINE_KEEP_NVRAM | libvirt.VIR_DOMAIN_UNDEFINE_KEEP_TPM
    )
    log(f"undefined guest '{current}' ({uuid}); its files stay in {spec['stateDir']}")


def fingerprint(paths: list[Path]) -> list[tuple[str, int, int]]:
    """Record the size and modification time of every file under the paths."""
    files = []
    for path in paths:
        members = [path] if path.is_file() else sorted(p for p in path.rglob("*") if p.is_file())
        for member in members:
            info = member.stat()
            files.append((str(member), info.st_size, info.st_mtime_ns))
    return files


def check_shut_off(domain: libvirt.virDomain, name: str) -> None:
    """Refuse a guest whose files may change: running, paused, or managed-saved."""
    if domain.state()[0] != libvirt.VIR_DOMAIN_SHUTOFF:
        msg = f"guest '{name}' is not shut off; shut it down so its files hold still"
        raise ReconcileError(msg)
    if domain.hasManagedSaveImage(0):
        msg = f"guest '{name}' has a managed save image; start and shut it down first"
        raise ReconcileError(msg)


def golden_sources(spec: dict) -> list[Path]:
    """Return the disks, NVRAM, and TPM state directory of a guest."""
    state = Path(spec["stateDir"])
    sources = [Path(path) for path in spec["disks"]] + [Path(spec["nvram"])]
    if (state / "tpm").exists():
        sources.append(state / "tpm")
    return sources


def copy_golden(conn: libvirt.virConnect, spec: dict, directory: Path) -> None:
    """Copy a shut-off guest's disks, NVRAM, TPM state, and definition, keeping holes."""
    name, uuid = spec["name"], spec["uuid"]
    domain = owned_domain(conn, uuid)
    if domain is None:
        msg = f"guest '{name}' ({uuid}) is not defined"
        raise ReconcileError(msg)
    check_shut_off(domain, name)
    target = directory / uuid
    if target.exists():
        msg = f"{target} exists; move it aside to keep it, or delete it to replace it"
        raise ReconcileError(msg)

    sources = golden_sources(spec)
    before = fingerprint(sources)
    partial = directory / f".{uuid}.partial"
    if partial.exists():
        shutil.rmtree(partial)
    partial.mkdir(mode=0o700)
    try:
        subprocess.run(
            ["cp", "--archive", "--sparse=always", "--", *map(str, sources), str(partial)],
            check=True,
            capture_output=True,
            text=True,
        )
        (partial / "domain.xml").write_text(domain.XMLDesc(libvirt.VIR_DOMAIN_XML_INACTIVE))
        check_shut_off(domain, name)
        # A start during the copy, even one shut down again, leaves a torn copy.
        changed = fingerprint(sources) != before
    except BaseException:
        shutil.rmtree(partial, ignore_errors=True)
        raise
    if changed:
        shutil.rmtree(partial)
        msg = f"the files of guest '{name}' changed during the copy; keep it shut off and retry"
        raise ReconcileError(msg)
    partial.rename(target)
    log(f"copied guest '{name}' to {target}")


def report_orphans(conn: libvirt.virConnect, declared: dict[str, list[str]]) -> None:
    """Warn about marked objects that no declaration names."""
    networks = set(declared["networks"])
    for network in conn.listAllNetworks(0):
        if network.UUIDString() not in networks and network_marked(network):
            warn(
                f"network '{network.name()}' ({network.UUIDString()}) is owned but undeclared; "
                "remove it by hand once no guest uses it"
            )
    guests = set(declared["guests"])
    for domain in conn.listAllDomains(0):
        if domain.UUIDString() not in guests and domain_marker(domain, 0) is not None:
            warn(
                f"guest '{domain.name()}' ({domain.UUIDString()}) is owned but undeclared; "
                'declare it with ensure = "absent" to undefine it and keep its files'
            )


def sha256_of(path: Path) -> str:
    """Hash a file."""
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def check_digest(path: Path, digest: str, sha256: str | None) -> None:
    """Fail when a digest differs from the declared one."""
    if sha256 is not None and digest != sha256:
        msg = f"{path} has SHA-256 {digest}, declared {sha256}"
        raise ReconcileError(msg)


def verify(path: Path, sha256: str | None) -> None:
    """Fail when a file does not match its declared hash."""
    if sha256 is not None:
        check_digest(path, sha256_of(path), sha256)


def read_source(path: Path) -> None:
    """Write the header and content of a regular file to stdout."""
    # O_NONBLOCK keeps a FIFO from blocking the open; fstat then rejects it.
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
    with os.fdopen(fd, "rb") as stream:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            msg = f"{path} is not a regular file"
            raise ReconcileError(msg)
        out = sys.stdout.buffer
        out.write(HEADER.pack(info.st_size, info.st_mtime_ns))
        shutil.copyfileobj(stream, out, CHUNK)
        out.flush()


def copy_as_owner(source: Path, out: BinaryIO, owner: str) -> tuple[str, int]:
    """Copy a source read with the owner's credentials; return its SHA-256 and mtime."""
    account = pwd.getpwnam(owner)
    command = [sys.executable, "-I", __file__, "read-source", str(source)]
    digest = hashlib.sha256()
    copied = 0
    size = mtime_ns = -1
    with subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        user=account.pw_uid,
        group=account.pw_gid,
        extra_groups=os.getgrouplist(owner, account.pw_gid),
    ) as reader:
        stdout = reader.stdout
        header = stdout.read(HEADER.size) if stdout is not None else b""
        if len(header) == HEADER.size and stdout is not None:
            size, mtime_ns = HEADER.unpack(header)
            while chunk := stdout.read(CHUNK):
                out.write(chunk)
                digest.update(chunk)
                copied += len(chunk)
    if reader.returncode != 0 or size < 0:
        msg = f"cannot read {source} as {owner}"
        raise ReconcileError(msg)
    if copied != size:
        msg = f"{source} changed while it was copied"
        raise ReconcileError(msg)
    return digest.hexdigest(), mtime_ns


def restore_ownership(target: Path, staged: os.stat_result) -> None:
    """Give a staged file back to root at 0644."""
    if (staged.st_uid, staged.st_gid) == (0, 0) and stat.S_IMODE(staged.st_mode) == STAGED_MODE:
        return
    os.chown(target, 0, 0)
    target.chmod(STAGED_MODE)
    log(f"reset {target} to root-owned 0644")


def stage(name: str, source: Path, target: Path, sha256: str | None, owner: str) -> None:
    """Copy a source file to its staged path unless an identical copy is there."""
    info = source.stat()
    staged = None
    with contextlib.suppress(FileNotFoundError):
        staged = target.lstat()
    if (
        staged is not None
        and stat.S_ISREG(staged.st_mode)
        and staged.st_size == info.st_size
        and staged.st_mtime_ns == info.st_mtime_ns
    ):
        restore_ownership(target, staged)
        verify(target, sha256)
        return

    partial = target.with_name(f".{name}.partial")
    partial.unlink(missing_ok=True)
    fd = os.open(partial, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC, 0o600)
    try:
        with os.fdopen(fd, "wb") as out:
            digest, mtime_ns = copy_as_owner(source, out, owner)
        check_digest(source, digest, sha256)
        os.utime(partial, ns=(mtime_ns, mtime_ns))
        partial.chmod(STAGED_MODE)
        partial.replace(target)
    except BaseException:
        partial.unlink(missing_ok=True)
        raise
    log(f"staged {source} as {target}")


def stage_media(manifest_path: Path, directory: Path, owner: str) -> None:
    """Stage every declared media file, then prune the undeclared ones."""
    manifest: dict[str, dict[str, str]] = json.loads(manifest_path.read_text())
    for name, spec in sorted(manifest.items()):
        source = Path(spec["source"])
        # Media are fetched by hand, so a missing one waits instead of failing the switch.
        if not source.exists():
            warn(
                f"{source} is missing, so '{name}' is not staged; put it in place and run "
                "`sudo systemctl restart workloads-vm-media.service`"
            )
            continue
        stage(name, source, directory / name, spec.get("sha256"), owner)

    for entry in sorted(directory.iterdir()):
        if entry.name in manifest:
            continue
        if entry.is_dir() and not entry.is_symlink():
            msg = f"{entry} is a directory; the media directory holds staged files only"
            raise ReconcileError(msg)
        entry.unlink()
        log(f"pruned {entry}")


def parser() -> argparse.ArgumentParser:
    """Describe the subcommands."""
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    network = commands.add_parser("network", help="define one rendered network")
    network.add_argument("xml", type=Path)
    network.add_argument("--autostart", action="store_true")
    network.add_argument("--start", action="store_true", help="start it without libvirt autostart")
    network.add_argument("--connect", default="qemu:///system")

    guest = commands.add_parser("guest", help="define or undefine one declared guest")
    guest.add_argument("spec", type=Path)
    guest.add_argument("--connect", default="qemu:///system")

    orphans = commands.add_parser("orphans", help="warn about owned objects nothing declares")
    orphans.add_argument("declared", type=Path)
    orphans.add_argument("--connect", default="qemu:///system")

    golden = commands.add_parser("golden", help="copy a shut-off guest to its golden directory")
    golden.add_argument("manifest", type=Path)
    golden.add_argument("name")
    golden.add_argument("--directory", type=Path, default=Path("/var/lib/workloads/golden"))
    golden.add_argument("--connect", default="qemu:///system")

    media = commands.add_parser("media", help="stage declared media and prune the rest")
    media.add_argument("manifest", type=Path)
    media.add_argument("directory", type=Path)
    media.add_argument("--owner", required=True, help="account whose credentials read sources")

    source = commands.add_parser("read-source", help="stream one source file for `media`")
    source.add_argument("path", type=Path)
    return parser


def run_connected(conn: libvirt.virConnect, args: argparse.Namespace) -> None:
    """Run one subcommand that talks to libvirt."""
    if args.command == "network":
        reconcile_network(conn, args.xml.read_text(), autostart=args.autostart, start=args.start)
    elif args.command == "guest":
        spec = json.loads(args.spec.read_text())
        if spec["ensure"] == "absent":
            remove_guest(conn, spec)
        else:
            reconcile_guest(conn, spec)
    elif args.command == "golden":
        guests = json.loads(args.manifest.read_text())
        if args.name not in guests:
            msg = f"no declared guest is named '{args.name}'"
            raise ReconcileError(msg)
        copy_golden(conn, {"name": args.name, **guests[args.name]}, args.directory)
    else:
        report_orphans(conn, json.loads(args.declared.read_text()))


def run(args: argparse.Namespace) -> None:
    """Run one subcommand."""
    if args.command in {"network", "guest", "orphans", "golden"}:
        # Expected lookup misses would otherwise print to stderr.
        libvirt.registerErrorHandler(lambda _ctx, _error: None, None)
        conn = libvirt.open(args.connect)
        try:
            run_connected(conn, args)
        finally:
            conn.close()
    elif args.command == "media":
        stage_media(args.manifest, args.directory, args.owner)
    else:
        read_source(args.path)


def main() -> int:
    """Run the subcommand the arguments name."""
    args = parser().parse_args()
    try:
        run(args)
    except subprocess.CalledProcessError as error:
        print(f"<3>error: {error}: {error.stderr.strip()}", file=sys.stderr)
        return 1
    except (ReconcileError, libvirt.libvirtError, OSError) as error:
        print(f"<3>error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
