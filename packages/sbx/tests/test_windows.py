# Copyright (c) 2026 Bad3r
"""Windows sandboxes against a fake guest agent that emulates the guest's tar and PowerShell."""

import base64
import dataclasses
import json
import tarfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path, PureWindowsPath
from typing import IO, TYPE_CHECKING, Any, cast

from sbx import cli, model, windows
from sbx.errors import SbxError
from sbx.sandboxes import Sandboxes
from sbx.windows import WindowsSettings

from . import test_core
from .test_core import NOW, FakeBackend

if TYPE_CHECKING:
    from sbx.config import Settings

FIRMWARE = "/nix/store/ovmf/FV/OVMF_CODE.fd"
VERSIONS = ("20261001T000000Z", "20261002T000000Z")


def _b64(data: bytes) -> str:
    return base64.b64encode(data).decode()


class FakeWindows(FakeBackend):
    """A guest agent whose C: drive is a host directory."""

    def __init__(self, drive: Path) -> None:
        """Start with an empty drive and no processes."""
        super().__init__()
        self.drive = drive
        self.processes: dict[int, dict[str, Any] | None] = {}
        self.handles: dict[int, IO[bytes]] = {}
        self.commands: list[list[str]] = []
        self.hang: set[str] = set()
        self.kill_exit = 0
        self.link_in_pack = False
        self.stall_reads = False
        self.exit_on_kill = False
        self.short_writes = False
        self.fail_remove = False
        self.counter = 100

    def host(self, path: str) -> Path:
        """Map a guest path on C: to the drive directory."""
        parsed = PureWindowsPath(path)
        if parsed.drive != "C:":
            raise AssertionError(path)
        return self.drive.joinpath(*parsed.parts[1:])

    def agent(self, domain: str, command: dict[str, object], timeout: int) -> dict[str, Any]:  # noqa: ARG002
        """Answer the agent commands sbx sends to Windows."""
        execute = command["execute"]
        arguments = cast("dict[str, Any]", command.get("arguments", {}))
        self.counter += 1
        match execute:
            case "guest-ping":
                value: object = {}
            case "guest-exec":
                argv = [arguments["path"], *arguments["arg"]]
                self.commands.append(argv)
                stdin = base64.b64decode(arguments.get("input-data", ""))
                running = argv[0] in self.hang
                self.processes[self.counter] = None if running else self.program(argv, stdin)
                value = {"pid": self.counter}
            case "guest-exec-status":
                status = self.processes[arguments["pid"]]
                value = {"exited": False} if status is None else {"exited": True, **status}
            case "guest-file-open":
                target = self.host(arguments["path"])
                self.handles[self.counter] = target.open(arguments["mode"])
                value = self.counter
            case "guest-file-write":
                data = base64.b64decode(arguments["buf-b64"])
                written = self.handles[arguments["handle"]].write(data)
                value = {"count": written - int(self.short_writes), "eof": False}
            case "guest-file-read":
                handle = self.handles[arguments["handle"]]
                data = b"" if self.stall_reads else handle.read(arguments["count"])
                eof = not data and not self.stall_reads
                value = {"count": len(data), "buf-b64": _b64(data), "eof": eof}
            case "guest-file-close":
                self.handles.pop(arguments["handle"]).close()
                value = {}
            case _:
                raise AssertionError(execute)
        return {"return": value}

    def program(self, argv: list[str], stdin: bytes) -> dict[str, Any]:
        """Emulate the guest programs sbx runs; anything else echoes its arguments."""
        if argv[0] == windows.TASKKILL:
            if self.exit_on_kill:
                for pid, status in self.processes.items():
                    if status is None:
                        self.processes[pid] = {"exitcode": 1}
            return {"exitcode": self.kill_exit, "err-data": _b64(b"not found")}
        if argv[0] != windows.POWERSHELL:
            return {"exitcode": 3, "out-data": _b64(" ".join(argv[1:]).encode())}
        return self.powershell(base64.b64decode(argv[-1]).decode("utf-16-le"), json.loads(stdin))

    def powershell(self, script: str, data: dict[str, str]) -> dict[str, Any]:
        """Emulate the PowerShell operations sbx runs through the guest's tar.exe."""
        if windows.EXTRACT in script:
            destination = self.host(data["destination"])
            destination.mkdir(parents=True, exist_ok=True)
            archive = self.host(data["archive"])
            with tarfile.open(archive) as tar:
                tar.extractall(destination, filter="data")
            archive.unlink()
        elif windows.PACK in script:
            parent = self.host(data["parent"])
            with tarfile.open(self.host(data["archive"]), "w") as tar:
                tar.add(parent / data["leaf"], arcname=data["leaf"])
                if self.link_in_pack:
                    link = tarfile.TarInfo(f"{data['leaf']}/link")
                    link.type = tarfile.SYMTYPE
                    link.linkname = "/etc/passwd"
                    tar.addfile(link)
        elif windows.REMOVE in script:
            if self.fail_remove:
                return {"exitcode": 1, "err-data": _b64(b"access denied")}
            self.host(data["path"]).unlink(missing_ok=True)
        else:
            raise AssertionError(script)
        return {"exitcode": 0}


class WindowsTest(unittest.TestCase):
    """Rendering, ceilings, commands, copies, and export pruning of Windows sandboxes."""

    def setUp(self) -> None:
        """Reuse the core fixture, then add two exports of a Windows base."""
        # A module reference, so discovery does not collect the core suite a second time.
        fixture = test_core.SandboxesTest("test_parsers")
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        self.scratch = fixture.scratch
        self.paths = fixture.paths
        self.base_dir = self.paths.bases / "win11"
        for version in VERSIONS:
            directory = self.base_dir / version
            (directory / windows.TPM).mkdir(parents=True)
            for name in (windows.DISK, windows.NVRAM, f"{windows.TPM}/tpm2-00.permall"):
                (directory / name).write_bytes(name.encode())
                (directory / name).chmod(0o400)
        (self.base_dir / ".partial-20261003T000000Z").mkdir()
        self.settings: Settings = dataclasses.replace(
            fixture.settings,
            windows=WindowsSettings(FIRMWARE, 4096, {"win11": self.base_dir}, "sbx-base"),
            file_bytes=12 << 30,
        )
        drive = self.scratch / "drive"
        (drive / "Windows" / "Temp").mkdir(parents=True)
        self.backend = FakeWindows(drive)

    def sandboxes(self) -> Sandboxes:
        """Bind the fake guest at a fixed clock."""
        return Sandboxes(
            self.settings, self.paths, lambda _slice: self.backend, "claude:one", lambda: NOW
        )

    def create(self, name: str = "w") -> dict[str, object]:
        """Create a Windows sandbox with default flags."""
        sandboxes = self.sandboxes()
        request = sandboxes.request(
            "win11", name=name, net="none", memory=None, cpus=None, ttl=None
        )
        return sandboxes.create(request)

    def test_domain(self) -> None:
        """The domain boots the export's firmware with its own NVRAM and TPM, without vsock."""
        self.create()
        directory = self.paths.sandbox("w")
        root = ET.fromstring(self.backend.xml["sbx-w"])  # noqa: S314
        loader = root.find("os/loader")
        self.assertIsNotNone(loader)
        self.assertEqual(loader.text, FIRMWARE)  # pyright: ignore[reportOptionalMemberAccess]
        self.assertEqual(loader.get("secure"), "yes")  # pyright: ignore[reportOptionalMemberAccess]
        self.assertEqual(root.findtext("os/nvram"), str(directory / windows.VARS))
        self.assertIsNone(root.find("os").get("firmware"))  # pyright: ignore[reportOptionalMemberAccess]
        self.assertEqual(root.find("features/smm").get("state"), "on")  # pyright: ignore[reportOptionalMemberAccess]
        self.assertIsNotNone(root.find("features/hyperv/synic"))
        self.assertEqual(root.find("clock").get("offset"), "localtime")  # pyright: ignore[reportOptionalMemberAccess]
        source = root.find("devices/tpm/backend/source")
        self.assertEqual(source.get("path"), str(directory / windows.TPM))  # pyright: ignore[reportOptionalMemberAccess]
        self.assertEqual(root.find("devices/disk/driver").get("error_policy"), "stop")  # pyright: ignore[reportOptionalMemberAccess]
        for absent in ("sysinfo", "devices/vsock", "devices/interface", "devices/graphics"):
            self.assertIsNone(root.find(absent), absent)
        self.assertEqual(root.findtext("memory"), "4096")
        newest = self.base_dir / VERSIONS[-1]
        self.assertEqual((directory / "base").readlink(), newest)
        self.assertEqual((directory / windows.VARS).read_bytes(), windows.NVRAM.encode())
        self.assertEqual((directory / windows.VARS).stat().st_mode & 0o777, 0o600)
        self.assertEqual(
            (directory / windows.TPM / "tpm2-00.permall").stat().st_mode & 0o777, 0o600
        )
        self.assertFalse((directory / "id_ed25519").exists())
        self.assertEqual(self.sandboxes().info("w")["image"], str(newest / windows.DISK))

    def test_refusals(self) -> None:
        """No export, `base build`, and a network are refused with the export unit named."""
        sandboxes = self.sandboxes()
        with self.assertRaises(SbxError) as refused:
            sandboxes.base_build("win11")
        self.assertEqual(refused.exception.code, "base-export")
        self.assertIn("sbx-base@win11.service", str(refused.exception))
        with self.assertRaises(SbxError) as refused:
            sandboxes.request("win11", name="w", net="egress", memory=None, cpus=None, ttl=None)
        self.assertIn("without a network", str(refused.exception))
        for version in VERSIONS:
            for path in sorted((self.base_dir / version).rglob("*"), reverse=True):
                path.unlink() if path.is_file() else path.rmdir()
            (self.base_dir / version).rmdir()
        with self.assertRaises(SbxError) as refused:
            self.create()
        self.assertEqual(refused.exception.code, "base-missing")
        self.assertIn("systemctl start sbx-base@win11.service", str(refused.exception))
        self.assertFalse(self.paths.sandbox("w").exists())

    def test_disk_reservation(self) -> None:
        """A Windows sandbox reserves the file size limit, not its larger virtual disk."""
        self.settings = dataclasses.replace(self.settings, disk_cap_bytes=30 << 30)
        self.create("w1")
        self.create("w2")
        with self.assertRaises(SbxError) as refused:
            self.create("w3")
        self.assertEqual(refused.exception.code, "disk-full")
        # Two Windows overlays and one 8G Linux overlay pass the 30G cap too.
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().create(model.Request("nixos", "l1", "none", 2048, 2, 3600))
        self.assertEqual(refused.exception.code, "disk-full")

    def test_exec(self) -> None:
        """Commands run as given through guest-exec, with --json exit codes and no SSH."""
        self.create()
        leading, command = cli.split_command(["exec", "w", "--json", "--", "cmd.exe", "/c", "ver"])
        args = cli.build_parser().parse_args(leading)
        args.command = command
        result, code = cli.dispatch(self.sandboxes(), args, as_json=True)
        self.assertEqual(code, 3)
        self.assertEqual(cast("dict[str, object]", result)["stdout"], "/c ver")
        self.assertEqual(self.backend.commands[-1], ["cmd.exe", "/c", "ver"])
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().exec_attached("w", ["cmd.exe"], timeout=None)
        self.assertEqual(refused.exception.code, "agent-only")

    def test_timeout_kills_the_process_tree(self) -> None:
        """A timeout runs taskkill on the process tree and reports a failed kill."""
        self.create()
        self.backend.hang.add("slow.exe")
        result = self.sandboxes().exec_capture("w", ["slow.exe"], timeout=0, agent=False)
        self.assertTrue(result.timed_out)
        self.assertEqual(result.stderr, b"")
        hung = [pid for pid, status in self.backend.processes.items() if status is None]
        self.assertEqual(self.backend.commands[-1][:3], [windows.TASKKILL, "/PID", str(hung[0])])
        self.backend.kill_exit = 128
        result = self.sandboxes().exec_capture("w", ["slow.exe"], timeout=0, agent=False)
        self.assertIn(b"may still run: not found", result.stderr)
        # A process that exits while taskkill fails is no failed kill.
        self.backend.exit_on_kill = True
        result = self.sandboxes().exec_capture("w", ["slow.exe"], timeout=0, agent=False)
        self.assertEqual(result.stderr, b"")

    def test_copies(self) -> None:
        """Copies in land under the guest directory; copies out arrive in xfer."""
        self.create()
        sandboxes = self.sandboxes()
        tree = self.scratch / "tmp" / "work"
        (tree / "sub").mkdir(parents=True)
        (tree / "sub" / "file").write_text("x")
        result = sandboxes.copy(str(tree), r"w:C:\Users\Public\in")
        self.assertEqual(result["to"], r"w:C:\Users\Public\in")
        landed = self.backend.drive / "Users" / "Public" / "in" / "work" / "sub" / "file"
        self.assertEqual(landed.read_text(), "x")
        self.assertEqual(list((self.backend.drive / "Windows" / "Temp").iterdir()), [])
        with self.assertRaises(SbxError):
            sandboxes.copy(str(tree), "w:relative")

        report = self.backend.drive / "out" / "report"
        (report / "logs").mkdir(parents=True)
        (report / "logs" / "a.txt").write_text("a")
        result = sandboxes.copy(r"w:C:\out\report", None)
        copied = Path(str(result["to"]))
        self.assertEqual(copied, self.paths.sandbox("w") / "xfer" / "report")
        self.assertEqual((copied / "logs" / "a.txt").read_text(), "a")
        self.assertEqual(list((self.backend.drive / "Windows" / "Temp").iterdir()), [])
        for guest in ("C:\\", r"C:\out\.."):
            with self.subTest(guest=guest), self.assertRaises(SbxError):
                sandboxes.copy(f"w:{guest}", None)

    def test_copy_out_refusals(self) -> None:
        """A link, endless empty reads, or a copy past the budget leave nothing behind."""
        self.create()
        (self.backend.drive / "out" / "dir").mkdir(parents=True)
        (self.backend.drive / "out" / "dir" / "big").write_bytes(b"x" * (3 << 20))
        self.backend.stall_reads = True
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().copy(r"w:C:\out\dir", None)
        self.assertEqual(refused.exception.code, "agent-reply")
        self.backend.stall_reads = False
        self.backend.link_in_pack = True
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().copy(r"w:C:\out\dir", None)
        self.assertEqual(refused.exception.code, "path-denied")
        self.backend.link_in_pack = False
        self.settings = dataclasses.replace(self.settings, disk_cap_bytes=2 << 20)
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().copy(r"w:C:\out\dir", None)
        self.assertEqual(refused.exception.code, "disk-full")
        self.assertEqual(list((self.paths.sandbox("w") / "xfer").iterdir()), [])
        self.assertEqual(list((self.backend.drive / "Windows" / "Temp").iterdir()), [])

    def test_copy_out_charges_blocks(self) -> None:
        """Many small files are charged whole blocks, so they cannot slip past the budget."""
        self.create()
        many = self.backend.drive / "out" / "many"
        many.mkdir(parents=True)
        for index in range(2000):
            (many / str(index)).write_bytes(b"x")
        self.settings = dataclasses.replace(self.settings, disk_cap_bytes=4 << 20)
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().copy(r"w:C:\out\many", None)
        self.assertEqual(refused.exception.code, "disk-full")
        self.assertEqual(list((self.paths.sandbox("w") / "xfer").iterdir()), [])

    def test_cleanup_keeps_the_original_error(self) -> None:
        """A cleanup that fails after a failed transfer leaves the transfer's error standing."""
        self.create()
        tree = self.scratch / "tmp" / "work"
        tree.mkdir(parents=True)
        (tree / "file").write_text("x")
        self.backend.short_writes = True
        self.backend.fail_remove = True
        with self.assertRaises(SbxError) as refused:
            self.sandboxes().copy(str(tree), r"w:C:\Users\Public\in")
        self.assertIn("wrote less", str(refused.exception))

    def test_gc_prunes_superseded_exports(self) -> None:
        """Pruning keeps the newest export and any a sandbox uses, and skips partial ones."""
        older, used = (self.base_dir / version for version in VERSIONS)
        self.create()
        (self.base_dir / "20261003T000000Z" / windows.TPM).mkdir(parents=True)
        superseded = {"reason": "superseded export"}
        self.assertEqual(
            self.sandboxes().gc(dry_run=True), [{"name": f"win11/{VERSIONS[0]}", **superseded}]
        )
        self.assertTrue(older.exists())
        self.sandboxes().gc(dry_run=False)
        self.assertFalse(older.exists())
        self.assertTrue(used.exists())
        self.sandboxes().destroy("w")
        self.assertEqual(
            self.sandboxes().gc(dry_run=False), [{"name": f"win11/{VERSIONS[1]}", **superseded}]
        )
        self.assertTrue((self.base_dir / ".partial-20261003T000000Z").exists())
        listing = self.sandboxes().base_list()
        self.assertEqual(listing[-1]["versions"], ["20261003T000000Z"])


if __name__ == "__main__":
    unittest.main()
