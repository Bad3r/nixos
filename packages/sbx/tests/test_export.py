# Copyright (c) 2026 Bad3r
"""The golden copy export, run as the current user on both sides."""

import json
import os
import pwd
import sys
import tempfile
import unittest
from pathlib import Path

from sbx import export

# Runs the receiver from this source tree, as the launcher does from the store.
RECEIVER = [
    sys.executable,
    "-c",
    "import sys; from sbx.export import main; sys.exit(main(sys.argv[1:]))",
    "receive",
]


class ExportTest(unittest.TestCase):
    """Copies keep holes and modes, repeat only on change, and respect the floor."""

    def setUp(self) -> None:
        """Lay out a golden copy with a sparse disk."""
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.scratch = Path(scratch.name)
        self.golden = self.scratch / "golden"
        (self.golden / "tpm").mkdir(parents=True)
        with (self.golden / "root.qcow2").open("wb") as disk:
            disk.write(b"head")
            disk.seek(64 << 20)
            disk.write(b"tail")
        (self.golden / "nvram.fd").write_bytes(b"vars")
        (self.golden / "tpm" / "tpm2-00.permall").write_bytes(b"tpm")
        (self.golden / "domain.xml").write_text("<domain/>")
        self.directory = self.scratch / "home" / "bases" / "win11"
        self.spec = {
            "golden": str(self.golden),
            "disk": "root.qcow2",
            "directory": str(self.directory),
            "owner": pwd.getpwuid(os.geteuid()).pw_name,
            "minFreeBytes": 0,
        }

    def export(self, version: str) -> None:
        """Run one export with the given version name."""
        export.export(self.spec, "win11", version, RECEIVER)

    def test_export(self) -> None:
        """The export holds the disk, NVRAM, and TPM state, read-only, with holes kept."""
        self.export("20261001T000000Z")
        version = self.directory / "20261001T000000Z"
        disk = version / "disk.qcow2"
        self.assertEqual(disk.read_bytes(), (self.golden / "root.qcow2").read_bytes())
        self.assertLess(disk.stat().st_blocks * 512, 64 << 20)
        self.assertEqual((version / "nvram.fd").read_bytes(), b"vars")
        self.assertEqual((version / "tpm" / "tpm2-00.permall").read_bytes(), b"tpm")
        self.assertFalse((version / "domain.xml").exists())
        for path in (disk, version / "nvram.fd", version / "tpm" / "tpm2-00.permall"):
            self.assertEqual(path.stat().st_mode & 0o777, 0o400)
        self.assertEqual(version.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.directory.stat().st_mode & 0o777, 0o700)

    def test_repeat_only_on_change(self) -> None:
        """An unchanged golden copy is not exported again; a changed one is."""
        self.export("20261001T000000Z")
        self.export("20261002T000000Z")
        self.assertEqual([path.name for path in self.directory.iterdir()], ["20261001T000000Z"])
        os.utime(self.golden / "nvram.fd", ns=(1, 1))
        self.export("20261003T000000Z")
        self.assertEqual(
            sorted(path.name for path in self.directory.iterdir()),
            ["20261001T000000Z", "20261003T000000Z"],
        )

    def test_refusals(self) -> None:
        """A missing golden copy, a FIFO, a link, and the free-space floor stop the export."""
        missing = {**self.spec, "golden": str(self.scratch / "absent")}
        with self.assertRaises(export.ExportError) as refused:
            export.export(missing, "win11", "20261001T000000Z", RECEIVER)
        self.assertIn("workloads-golden@win11.service", str(refused.exception))

        floor = {**self.spec, "minFreeBytes": 1 << 62}
        with self.assertRaises(export.subprocess.CalledProcessError):
            export.export(floor, "win11", "20261001T000000Z", RECEIVER)
        self.assertEqual(list(self.directory.iterdir()), [])

        fifo = self.golden / "tpm" / "fifo"
        os.mkfifo(fifo)
        with self.assertRaises(export.ExportError):
            self.export("20261001T000000Z")
        fifo.unlink()

        (self.golden / "tpm" / "link").symlink_to(self.golden / "domain.xml")
        with self.assertRaises(OSError):
            self.export("20261001T000000Z")

    def test_receiver_checks_names(self) -> None:
        """The receiver writes only the base file names, under a valid version."""
        source = json.dumps([])
        for version, name in (("20261001T000000Z", "../escape"), ("latest", "nvram.fd")):
            with self.subTest(version=version, name=name), self.assertRaises(export.ExportError):
                export.receive(self.directory, version, [(0, name)], json.loads(source), 0)


if __name__ == "__main__":
    unittest.main()
