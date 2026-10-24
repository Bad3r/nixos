# Copyright (c) 2026 Bad3r
"""Define-only reconciler for declared workload objects.

`network` defines one rendered network and never destroys or restarts it.
`media` stages declared media files and prunes the ones no longer declared.
"""

import argparse
import hashlib
import json
import os
import shutil
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

import libvirt

MARKER = "{https://github.com/Bad3r/nixos/workloads}managed"
# The gateway of the network libvirtd-config copies from the package.
STOCK_DEFAULT_GATEWAY = "192.168.122.1"


class ReconcileError(Exception):
    """A declaration conflicts with the host's current state."""


def log(message: str) -> None:
    """Print one journal line."""
    print(message, flush=True)


def parse(xml: str) -> ET.Element:
    """Parse XML that libvirt or the Nix renderer produced."""
    return ET.fromstring(xml)  # noqa: S314


def is_marked(root: ET.Element) -> bool:
    """Return whether an object carries the workloads ownership marker."""
    return root.find(f"metadata/{MARKER}") is not None


def canonical(root: ET.Element) -> str:
    """Serialize a network definition without its runtime-only attributes."""
    root.attrib.pop("connections", None)
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


def reconcile_network(conn: libvirt.virConnect, xml: str, *, autostart: bool) -> None:
    """Define a declared network; start it when it is inactive and autostarts."""
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
        live = canonical(parse(network.XMLDesc(0)))
        if live != canonical(inactive_xml(network)):
            log(
                f"network '{name}' runs an older definition until it restarts; "
                f"`virsh net-destroy {name} && virsh net-start {name}` applies it "
                "and drops the link of every attached guest"
            )
    elif autostart:
        network.create()
        log(f"started network '{name}'")


def sha256_of(path: Path) -> str:
    """Hash a file."""
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify(path: Path, sha256: str | None) -> None:
    """Fail when a file does not match its declared hash."""
    if sha256 is None:
        return
    digest = sha256_of(path)
    if digest != sha256:
        msg = f"{path} has SHA-256 {digest}, declared {sha256}"
        raise ReconcileError(msg)


def stage(name: str, source: Path, target: Path, sha256: str | None) -> None:
    """Copy a source file to its staged path unless an identical copy is there."""
    info = source.stat()
    try:
        staged = target.stat()
    except FileNotFoundError:
        staged = None
    if (
        staged is not None
        and staged.st_size == info.st_size
        and staged.st_mtime_ns == info.st_mtime_ns
    ):
        verify(target, sha256)
        return

    partial = target.with_name(f".{name}.partial")
    shutil.copyfile(source, partial)
    partial.chmod(0o644)
    os.utime(partial, ns=(info.st_atime_ns, info.st_mtime_ns))
    verify(partial, sha256)
    partial.replace(target)
    log(f"staged {source} as {target}")


def stage_media(manifest_path: Path, directory: Path) -> None:
    """Stage every declared media file, then prune the undeclared ones."""
    manifest: dict[str, dict[str, str]] = json.loads(manifest_path.read_text())
    for name, spec in sorted(manifest.items()):
        stage(name, Path(spec["source"]), directory / name, spec.get("sha256"))

    for entry in sorted(directory.iterdir()):
        if entry.name in manifest:
            continue
        if entry.is_dir() and not entry.is_symlink():
            msg = f"{entry} is a directory; the media directory holds staged files only"
            raise ReconcileError(msg)
        entry.unlink()
        log(f"pruned {entry}")


def main() -> int:
    """Run one subcommand."""
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    network = commands.add_parser("network", help="define one rendered network")
    network.add_argument("xml", type=Path)
    network.add_argument("--autostart", action="store_true")
    network.add_argument("--connect", default="qemu:///system")

    media = commands.add_parser("media", help="stage declared media and prune the rest")
    media.add_argument("manifest", type=Path)
    media.add_argument("directory", type=Path)

    args = parser.parse_args()
    try:
        if args.command == "network":
            # Expected lookup misses would otherwise print to stderr.
            libvirt.registerErrorHandler(lambda _ctx, _error: None, None)
            conn = libvirt.open(args.connect)
            try:
                reconcile_network(conn, args.xml.read_text(), autostart=args.autostart)
            finally:
                conn.close()
        else:
            stage_media(args.manifest, args.directory)
    except (ReconcileError, libvirt.libvirtError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
