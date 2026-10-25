# Copyright (c) 2026 Bad3r
"""The QEMU launcher's namespace checks, descriptor rebinding, and confined root."""

import json
import os
import stat
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
            mock.patch.object(emulator, "confine") as confine,
        ):
            with self.assertRaises(SystemExit) as stopped:
                emulator.main("/qemu", ["-S"])
            self.assertEqual(stopped.exception.code, 1)
            private.assert_called_once_with(os.getuid(), os.getgid())
            rebind.assert_not_called()
            confine.assert_not_called()
            execv.assert_not_called()
            mode.write_text("local\n")
            emulator.main("/qemu", ["-S", "-pidfile", "/run/probe/qmp.pid"])
            self.assertIn(emulator.Bind("/run/probe", writable=True), confine.call_args.args[0])
            execv.assert_called_once_with(
                "/qemu", ["/qemu", "-S", "-pidfile", "/run/probe/qmp.pid"]
            )

    def test_main_refuses_when_confinement_fails(self) -> None:
        """QEMU never starts outside its confined root."""
        mode = self.scratch / "ns_mode"
        mode.write_text("local\n")
        with (
            mock.patch.object(emulator, "NS_MODE", mode),
            mock.patch.object(emulator, "private_namespace"),
            mock.patch.object(emulator, "device_fds", return_value=[]),
            mock.patch.object(emulator, "confine", side_effect=emulator.LaunchError("no mount")),
            mock.patch.object(emulator.os, "execv") as execv,
            self.assertRaises(SystemExit),
        ):
            emulator.main("/qemu", ["-S"])
        execv.assert_not_called()

    def test_options(self) -> None:
        """A doubled comma stays in the value; a bare field maps to the empty string."""
        self.assertEqual(
            emulator.options("socket,id=c,path=/a,,b,server=on"),
            {"socket": "", "id": "c", "path": "/a,b", "server": "on"},
        )
        self.assertEqual(emulator.fields("unix:/x/qmp,server=on"), ["unix:/x/qmp", "server=on"])

    def test_qemu_binds(self) -> None:
        """Files libvirt names come in, read-only where every reader is; descriptors stay out."""
        lib = "/home/o/.config/libvirt/qemu/lib/domain-1-sbx-v"
        run = "/home/o/.local/share/sbx/v"
        secret = {"qom-type": "secret", "id": "masterKey0", "format": "raw"}
        argv = [
            "-name",
            "guest=sbx-v,debug-threads=on",
            "-object",
            json.dumps({**secret, "file": f"{lib}/master-key.aes"}),
            "-blockdev",
            '{"driver":"file","filename":"/nix/store/x-code.fd","node-name":"p0"}',
            "-blockdev",
            '{"node-name":"p0f","read-only":true,"driver":"raw","file":"p0"}',
            "-blockdev",
            f'{{"driver":"file","filename":"{run}/VARS.fd","node-name":"p1","read-only":false}}',
            "-blockdev",
            '{"driver":"file","filename":"/home/o/.local/share/sbx/bases/b/disk.qcow2","node-name":"b"}',
            "-blockdev",
            '{"node-name":"bf","read-only":true,"driver":"qcow2","file":"b","backing":null}',
            "-blockdev",
            f'{{"driver":"file","filename":"{run}/disk.qcow2","node-name":"d"}}',
            "-blockdev",
            '{"node-name":"df","read-only":false,"driver":"qcow2","file":"d","backing":"bf"}',
            "-add-fd",
            "set=0,fd=27,opaque=serial0-source",
            "-chardev",
            "file,id=charserial0,path=/dev/fdset/0,append=on",
            "-chardev",
            "socket,id=charmonitor,fd=28,server=on,wait=off",
            "-chardev",
            "socket,id=chrtpm,path=/run/user/1/libvirt/qemu/run/swtpm/1-sbx-v-swtpm.sock",
            "-spice",
            f"unix=on,addr={lib}/spice.sock,disable-ticketing=on",
        ]
        with mock.patch.object(emulator, "LOCALTIME", str(self.scratch / "localtime")):
            binds = emulator.qemu_binds(argv)
        self.assertCountEqual(
            binds,
            [
                emulator.Bind(lib, writable=True),
                emulator.Bind("/nix/store/x-code.fd", writable=False),
                emulator.Bind(f"{run}/VARS.fd", writable=True),
                emulator.Bind("/home/o/.local/share/sbx/bases/b/disk.qcow2", writable=False),
                emulator.Bind(f"{run}/disk.qcow2", writable=True),
                emulator.Bind(
                    "/run/user/1/libvirt/qemu/run/swtpm/1-sbx-v-swtpm.sock", writable=True
                ),
                emulator.Bind(f"{lib}/spice.sock", writable=True),
            ],
        )
        with self.assertRaises(emulator.LaunchError):
            emulator.qemu_binds(["-blockdev", "driver=file,filename=/dev/sda"])

    def test_swtpm_binds(self) -> None:
        """The state, the log, and the socket's directory come in; capability probes need none."""
        argv = [
            "socket",
            "--ctrl",
            "type=unixio,path=/run/swtpm/v-swtpm.sock,mode=0600",
            "--tpmstate",
            "dir=/home/o/.local/share/sbx/v/tpm,mode=0600,lock",
            "--log",
            "file=/home/o/.cache/libvirt/qemu/log/sbx-v-swtpm.log",
            "--terminate",
            "--tpm2",
        ]
        self.assertEqual(
            emulator.swtpm_binds(argv),
            [
                emulator.Bind("/run/swtpm", writable=True),
                emulator.Bind("/home/o/.local/share/sbx/v/tpm", writable=True),
                emulator.Bind("/home/o/.cache/libvirt/qemu/log/sbx-v-swtpm.log", writable=True),
            ],
        )
        self.assertEqual(emulator.swtpm_binds(["socket", "--print-capabilities"]), [])

    def test_plan(self) -> None:
        """Parents come first, a bound directory hides its children, and writable wins a tie."""
        planned = emulator.plan(
            [
                emulator.Bind("/nix/store/x-base.qcow2", writable=False),
                emulator.Bind("/home/o/lib/spice.sock", writable=True),
                emulator.Bind("/home/o/run/disk.qcow2", writable=False),
                emulator.Bind("/home/o/run//disk.qcow2", writable=True),
                emulator.Bind("/home/o/lib", writable=True),
                emulator.Bind("/nix/store", writable=False),
            ]
        )
        self.assertEqual(
            planned,
            [
                emulator.Bind("/home/o/lib", writable=True),
                emulator.Bind("/home/o/run/disk.qcow2", writable=True),
                emulator.Bind("/nix/store", writable=False),
            ],
        )
        with self.assertRaises(emulator.LaunchError):
            emulator.plan([emulator.Bind("relative/disk.qcow2", writable=True)])

    def test_bind_refuses_devices(self) -> None:
        """A block device never comes in, and a character device only from the device list."""
        target = str(self.scratch / "target")
        with mock.patch.object(emulator, "_mount") as mount:
            with self.assertRaises(emulator.LaunchError):
                emulator.mount_bind("/dev/null", target, writable=True, device=False)
            block = os.stat_result((stat.S_IFBLK | 0o660, 0, 0, 1, 0, 6, 0, 0, 0, 0))
            with (
                mock.patch.object(emulator.os, "stat", return_value=block),
                self.assertRaises(emulator.LaunchError),
            ):
                emulator.mount_bind("/dev/dm-0", target, writable=True, device=True)
            mount.assert_not_called()
            emulator.mount_bind("/dev/null", target, writable=True, device=True)
            mount.assert_called_once_with(
                "/dev/null", target, None, emulator.MS_BIND | emulator.MS_REC
            )

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
