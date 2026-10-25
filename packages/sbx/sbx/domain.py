# Copyright (c) 2026 Bad3r
"""The one domain template every sandbox boots from."""

import xml.etree.ElementTree as ET
from typing import TYPE_CHECKING

from sbx import cloud, windows
from sbx.context import Context
from sbx.model import DOMAIN_PREFIX, GUI_BASES
from sbx.net import bridge_interface

if TYPE_CHECKING:
    from pathlib import Path

    from sbx.config import Egress
    from sbx.model import Meta, Request


# systemd-tmpfiles writes /root/.ssh/authorized_keys from this credential.
CREDENTIAL = "opt/io.systemd.credentials/ssh.authorized_keys.root"
# Runtime shares one sandbox can hold at once.
SHARE_SLOTS = 4


class DomainXml(Context):
    """Rendering of a sandbox's domain definition."""

    def _domain_xml(  # noqa: PLR0913, PLR0915, PLR0917
        self,
        name: str,
        directory: Path,
        meta: Meta,
        request: Request,
        authorized_key: str,
        nic: tuple[Egress, str] | None,
    ) -> str:
        domain = ET.Element("domain", type="kvm")

        def sub(parent: ET.Element, tag: str, text: str | None = None, **attrs: str) -> ET.Element:
            element = ET.SubElement(parent, tag, attrs)
            element.text = text
            return element

        cpuset = self.settings.cpuset
        sub(domain, "name", DOMAIN_PREFIX + name)
        sub(domain, "metadata").append(meta.element())
        sub(domain, "memory", str(request.memory_mib), unit="MiB")
        # virtiofs, which `sbx share attach` hot-plugs, needs shared guest memory.
        backing = sub(domain, "memoryBacking")
        sub(backing, "source", type="memfd")
        sub(backing, "access", mode="shared")
        # The user manager has no cpuset controller, so pinning goes through affinity.
        sub(domain, "vcpu", str(request.cpus), placement="static", cpuset=cpuset)
        sub(sub(domain, "cputune"), "emulatorpin", cpuset=cpuset)
        system = sub(domain, "os", firmware="efi")
        sub(system, "type", "hvm", arch="x86_64", machine="q35")
        firmware = sub(system, "firmware")
        sub(firmware, "feature", enabled="no", name="secure-boot")
        sub(system, "nvram", str(directory / "VARS.fd"))
        sub(system, "boot", dev="hd")
        seeded = request.base in self.settings.cloud_images
        if not seeded:
            sysinfo = sub(domain, "sysinfo", type="fwcfg")
            sub(sysinfo, "entry", authorized_key, name=CREDENTIAL)
        features = sub(domain, "features")
        sub(features, "acpi")
        sub(features, "apic")
        sub(features, "vmport", state="off")
        cpu = sub(domain, "cpu", mode="host-passthrough", check="none")
        sub(cpu, "feature", policy="disable", name="vmx")
        sub(domain, "clock", offset="utc")
        sub(domain, "on_poweroff", "destroy")
        sub(domain, "on_reboot", "restart")
        sub(domain, "on_crash", "destroy")
        devices = sub(domain, "devices")
        sub(devices, "emulator", self.settings.tools.emulator)
        disk = sub(devices, "disk", type="file", device="disk")
        sub(disk, "driver", name="qemu", type="qcow2", cache="unsafe", discard="unmap")
        sub(disk, "source", file=str(directory / "disk.qcow2"))
        sub(disk, "target", dev="vda", bus="virtio")
        if seeded:
            seed = sub(devices, "disk", type="file", device="cdrom")
            sub(seed, "driver", name="qemu", type="raw")
            sub(seed, "source", file=str(directory / cloud.SEED))
            sub(seed, "target", dev="sda", bus="sata")
            sub(seed, "readonly")
        if nic is not None:
            egress, mac = nic
            devices.append(bridge_interface(egress.bridge, mac))
        sub(devices, "controller", type="usb", model="none")
        # Untrusted class: the guest agent channel only, never a vdagent channel.
        channel = sub(devices, "channel", type="unix")
        sub(channel, "source", mode="bind")
        sub(channel, "target", type="virtio", name="org.qemu.guest_agent.0")
        # The emulator rebinds it to QEMU's own local vsock namespace (sbx.emulator).
        vsock = sub(devices, "vsock", model="virtio")
        sub(vsock, "cid", auto="yes")
        serial = sub(devices, "serial", type="file")
        sub(serial, "source", path=str(directory / "console.log"))
        sub(serial, "target", port="0")
        # A display device without <graphics> gives screenshots and no console socket;
        # GUI bases add a SPICE socket for libvirt clients, still without clipboard or files.
        if request.base in GUI_BASES:
            graphics = sub(devices, "graphics", type="spice")
            sub(graphics, "listen", type="socket")
            sub(graphics, "image", compression="off")
            sub(graphics, "clipboard", copypaste="no")
            sub(graphics, "filetransfer", enable="no")
        video = sub(devices, "video")
        sub(video, "model", type="virtio", heads="1")
        rng = sub(devices, "rng", model="virtio")
        sub(rng, "backend", "/dev/urandom", model="random")
        sub(devices, "memballoon", model="virtio", freePageReporting="on")
        # libvirt keeps a hot-plug slot only in definitions without PCI controllers, and
        # cold devices take listed root ports first: one per device element covers them.
        ports = len(devices) + SHARE_SLOTS
        sub(devices, "controller", type="pci", index="0", model="pcie-root")
        for _ in range(ports):
            sub(devices, "controller", type="pci", model="pcie-root-port")
        return self._serialize(domain, directory, request.base)

    def _serialize(self, domain: ET.Element, directory: Path, base: str) -> str:
        """Render the domain, adapted first when `base` is a Windows base."""
        if (windows_settings := self.windows_base(base)) is not None:
            windows.adapt(domain, directory, windows_settings.firmware)
        return ET.tostring(domain, encoding="unicode")
