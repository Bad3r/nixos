# Copyright (c) 2026 Bad3r
"""The QEMU launcher's namespace checks and descriptor rebinding."""

import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from sbx import emulator


class EmulatorTest(unittest.TestCase):
    """QEMU starts only in a local vsock namespace, holding a device opened there."""

    def setUp(self) -> None:
        """Make a scratch directory."""
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.scratch = Path(scratch.name)

    def test_check_local(self) -> None:
        """Only a local namespace passes; a global one or a kernel without the sysctl fails."""
        mode = self.scratch / "ns_mode"
        mode.write_text("local\n")
        emulator.check_local(mode)
        mode.write_text("global\n")
        with self.assertRaises(emulator.LaunchError):
            emulator.check_local(mode)
        with self.assertRaises(emulator.LaunchError):
            emulator.check_local(self.scratch / "missing")

    def test_device_fds(self) -> None:
        """Descriptors are matched by device number, so other files and a missing node give none."""
        device = os.open("/dev/null", os.O_RDONLY)
        self.addCleanup(os.close, device)
        other = os.open(self.scratch, os.O_RDONLY)
        self.addCleanup(os.close, other)
        found = emulator.device_fds(emulator.FD_DIR, "/dev/null")
        self.assertIn(device, found)
        self.assertNotIn(other, found)
        self.assertEqual(emulator.device_fds(emulator.FD_DIR, str(self.scratch / "none")), [])

    def test_check_vhostfds(self) -> None:
        """Every vsock device needs a reopened descriptor, and every such descriptor a device."""
        vsock = '{"driver":"vhost-vsock-pci","id":"vsock0","guest-cid":3,"vhostfd":"28"}'
        emulator.check_vhostfds(["-machine", "none,accel=kvm", "-qmp", "unix:/x"], [])
        emulator.check_vhostfds(["-name", "guest=sbx-v", "-device", vsock], [28])
        refused: tuple[tuple[list[str], list[int]], ...] = (
            (["-device", vsock], []),
            (["-device", vsock], [27]),
            (["-device", vsock.replace('"28"', '"/dev/fdset/1"')], [28]),
            (["-device", '{"driver":"vhost-vsock-pci","id":"vsock0","guest-cid":3}'], []),
            (["-device", "vhost-vsock-pci,id=vsock0,vhostfd=28"], [28]),
            (["-name", "guest=sbx-v"], [28]),
        )
        for argv, fds in refused:
            with self.subTest(argv=argv, fds=fds), self.assertRaises(emulator.LaunchError):
                emulator.check_vhostfds(argv, fds)

    def test_rebind(self) -> None:
        """The descriptor number now holds the freshly opened device; the original stays open."""
        old, new = self.scratch / "old", self.scratch / "new"
        old.write_text("old")
        new.write_text("new")
        fd = os.open(old, os.O_RDONLY)
        self.addCleanup(os.close, fd)
        kept: list[int] = []
        real_dup = os.dup

        def dup(source: int) -> int:
            copy = real_dup(source)
            kept.append(copy)
            self.addCleanup(os.close, copy)
            return copy

        with mock.patch.object(emulator.os, "dup", side_effect=dup):
            emulator.rebind([fd], str(new))
        self.assertEqual(os.read(fd, 3), b"new")
        self.assertEqual([Path(f"/proc/self/fd/{copy}").readlink() for copy in kept], [old])
        self.assertTrue(os.get_inheritable(kept[0]))

    def test_main_refuses_outside_a_local_namespace(self) -> None:
        """A namespace that is not local stops the launch before QEMU runs."""
        mode = self.scratch / "ns_mode"
        mode.write_text("global\n")
        with (
            mock.patch.object(emulator, "NS_MODE", mode),
            mock.patch.object(emulator, "private_namespace") as private,
            mock.patch.object(emulator, "device_fds", return_value=[]),
            mock.patch.object(emulator.os, "execv") as execv,
            mock.patch.object(emulator, "rebind") as rebind,
        ):
            with self.assertRaises(SystemExit) as stopped:
                emulator.main("/qemu", ["-S"])
            self.assertEqual(stopped.exception.code, 1)
            private.assert_called_once_with(os.getuid(), os.getgid())
            rebind.assert_not_called()
            execv.assert_not_called()
            mode.write_text("local\n")
            emulator.main("/qemu", ["-S"])
            execv.assert_called_once_with("/qemu", ["/qemu", "-S"])

    def test_main_refuses_an_unreopened_vsock_device(self) -> None:
        """A vsock device without an inherited descriptor stops the launch before any namespace."""
        argv = ["-device", '{"driver":"vhost-vsock-pci","id":"vsock0","vhostfd":"28"}']
        with (
            mock.patch.object(emulator, "device_fds", return_value=[]),
            mock.patch.object(emulator, "private_namespace") as private,
            mock.patch.object(emulator.os, "execv") as execv,
            self.assertRaises(SystemExit),
        ):
            emulator.main("/qemu", argv)
        private.assert_not_called()
        execv.assert_not_called()


if __name__ == "__main__":
    unittest.main()
