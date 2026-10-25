# Copyright (c) 2026 Bad3r
"""Runtime shares of sandboxes against the core tests' fake backend."""

import base64
import dataclasses
import json
import shlex
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any, cast
from unittest import mock

from sbx.errors import SbxError
from sbx.sandboxes import Sandboxes
from sbx.shares import MAX_TARGETS, MOUNT_WAIT, UNMOUNT_WAIT, Shares, attached
from sbx.windows import WindowsSettings

from tests.test_core import NOW, FakeBackend, Fixture, dispatch


def _b64(text: str) -> str:
    return base64.b64encode(text.encode()).decode()


class ShareFake(FakeBackend):
    """Adds live virtiofs devices; a detached one lingers for `linger` polls, or forever.

    Guest helpers act on `mounts`, each tag's guest mountpoints in mount order.
    """

    def __init__(self) -> None:
        """No device is attached."""
        super().__init__()
        self.devices: dict[str, list[str]] = {}
        self.releasing: dict[str, tuple[str, int | None]] = {}
        self.linger: int | None = 2
        self.stuck: set[str] = set()
        self.vanished: set[str] = set()
        self.mounts: dict[str, list[str]] = {}
        self.guest_commands: list[list[str]] = []
        self.busy: set[str] = set()
        self.mount_fails = False
        # Mounts that fail before the guest has probed a hot-plugged device.
        self.unprobed = 0
        self.silent = False
        # The guest agent answers guest-exec with a malformed reply.
        self.garbled = False
        self.helper_statuses: dict[int, dict[str, Any]] = {}

    def _guest(self, argv: list[str]) -> dict[str, Any]:
        """Answer one guest helper as a NixOS guest would."""
        if argv[:2] == ["sh", "-c"]:
            if self.mount_fails or self.unprobed > 0:
                self.unprobed -= 1
                return {"exitcode": 32, "err-data": _b64("mount: unknown filesystem type")}
            words = shlex.split(argv[2])
            self.mounts.setdefault(words[-2], []).append(words[-1])
            return {"exitcode": 0}
        if argv[0] == "findmnt":
            if "-S" in argv:
                targets = self.mounts.get(argv[argv.index("-S") + 1], [])
                lines = "".join(f"{target}\n" for target in targets)
            else:
                lines = "".join(
                    f"{tag} {target}\n"
                    for tag, targets in self.mounts.items()
                    for target in targets
                )
            return {"exitcode": 0 if lines else 1, "out-data": _b64(lines)}
        if argv[0] == "umount":
            target = argv[-1]
            if target in self.busy and "-l" not in argv:
                return {"exitcode": 32, "err-data": _b64(f"umount: {target}: target is busy.")}
            for targets in self.mounts.values():
                if target in targets:
                    targets.remove(target)
            return {"exitcode": 0}
        raise AssertionError(argv)

    def agent(self, domain: str, command: dict[str, object], timeout: int) -> dict[str, Any]:
        """Run guest helpers against `mounts`; a silent guest answers nothing."""
        execute = command["execute"]
        if execute not in {"guest-exec", "guest-exec-status"}:
            return super().agent(domain, command, timeout)
        if self.silent:
            msg = "Guest agent is not responding: QEMU guest agent is not connected"
            raise SbxError(msg, code="libvirt")
        if self.garbled:
            return {"return": {"pid": "not a number"}}
        arguments = cast("dict[str, Any]", command["arguments"])
        if execute == "guest-exec-status":
            return {"return": self.helper_statuses.pop(arguments["pid"])}
        argv = [arguments["path"], *arguments["arg"]]
        helper = argv[argv.index("--") + 1 :]
        self.guest_commands.append(helper)
        pid = len(self.guest_commands)
        self.helper_statuses[pid] = {"exited": True, **self._guest(helper)}
        return {"return": {"pid": pid}}

    def live_xml(self, domain: str) -> str:
        """The devices, wrapped like a domain definition."""
        if domain in self.vanished:
            msg = f"no domain {domain}"
            raise SbxError(msg, code="not-found")
        devices = list(self.devices.get(domain, []))
        if domain in self.releasing:
            xml, left = self.releasing[domain]
            if left == 0:
                del self.releasing[domain]
            else:
                devices.append(xml)
                self.releasing[domain] = (xml, None if left is None else left - 1)
        return f"<domain><devices>{''.join(devices)}</devices></domain>"

    def attach_device(self, domain: str, xml: str) -> None:
        """Plug the device."""
        self.devices.setdefault(domain, []).append(xml)

    def detach_device(self, domain: str, xml: str) -> None:
        """Start releasing the device."""
        if domain in self.vanished:
            msg = f"no domain {domain}"
            raise SbxError(msg, code="not-found")
        self.devices[domain].remove(xml)
        self.releasing[domain] = (xml, None if domain in self.stuck else self.linger)


class SharesTest(Fixture):
    """shared read-write, declared directories read-only, nothing else."""

    def setUp(self) -> None:
        """Swap in the share-aware backend and write a policy file."""
        super().setUp()
        self.backend = ShareFake()
        self.docs = self.scratch / "docs"
        self.docs.mkdir()
        self.policy = self.scratch / "grants.json"
        declared = {
            "docs": self.docs,
            "home": Path.home(),
            "state": self.paths.root,
            "above": self.paths.root.parent,
            "gone": self.scratch / "gone",
        }
        self.policy.write_text(
            json.dumps({"sandboxShares": {k: {"hostPath": str(v)} for k, v in declared.items()}})
        )
        self.slept: list[float] = []
        self.now = 0.0

    def shares(self) -> Shares:
        """Shares over the fixture with a fake clock."""

        def sleep(seconds: float) -> None:
            self.slept.append(seconds)
            self.now += seconds

        return Shares(self.sandboxes(), self.policy, sleep=sleep, clock=lambda: self.now)

    def add_running(self, name: str, *, expires: int = NOW + 60) -> None:
        """Register a running sandbox with its run directory."""
        self.paths.sandbox(name).mkdir(parents=True)
        self.backend.add(name, expires=expires)

    def device(self, tag: str) -> ET.Element:
        """The live device of a tag."""
        return ET.fromstring(attached(self.backend.live_xml("sbx-s"))[tag].xml)  # noqa: S314

    def test_attach(self) -> None:
        """The shared directory attaches read-write, a declared one read-only, through virtiofsd."""
        self.add_running("s")
        shared = self.shares().attach("s", "shared")
        self.assertEqual(
            shared.as_json(),
            {
                "sandbox": "s",
                "tag": "shared",
                "read_only": False,
                "host_path": str(self.paths.sandbox("s").resolve() / "shared"),
                "attached": True,
                "mountpoint": "/mnt/shared",
                "mounted": True,
                "mount_command": "mkdir -p /mnt/shared && mount -t virtiofs shared /mnt/shared",
                "unmount_command": "umount /mnt/shared",
            },
        )
        self.assertTrue((self.paths.sandbox("s") / "shared").is_dir())
        self.assertIsNone(self.device("shared").find("readonly"))
        binary = self.device("shared").find("binary")
        self.assertEqual(binary.get("path"), self.settings.tools.virtiofsd)  # pyright: ignore[reportOptionalMemberAccess]
        self.assertTrue(self.shares().attach("s", "docs").read_only)
        self.assertIsNotNone(self.device("docs").find("readonly"))
        with self.assertRaises(SbxError) as refused:
            self.shares().attach("s", "shared")
        self.assertEqual(refused.exception.code, "already-attached")
        self.journal_record.assert_any_call(
            "share docs attached to s",
            verb="share",
            sandbox="s",
            share="docs",
            read_only=True,
            session="claude:one",
        )

    def test_refusals(self) -> None:
        """Undeclared names, $HOME, the state directory, and stopped sandboxes are refused."""
        self.add_running("s")
        self.add_running("old", expires=NOW - 1)
        self.backend.add("off", expires=NOW + 60, active=False)
        cases = [
            ("s", "nope", "not-declared"),
            ("s", str(self.docs), "not-declared"),
            ("s", "home", "path-denied"),
            ("s", "state", "path-denied"),
            ("s", "above", "path-denied"),
            ("s", "gone", "path-denied"),
            ("s", "xfer", "not-declared"),
            ("old", "shared", "expired"),
            ("off", "shared", "not-running"),
            ("missing", "shared", "not-found"),
        ]
        self.paths.sandbox("off").mkdir(parents=True)
        for name, tag, expected in cases:
            with self.subTest(name=name, tag=tag), self.assertRaises(SbxError) as refused:
                self.shares().attach(name, tag)
            self.assertEqual(refused.exception.code, expected)
        self.assertEqual(self.backend.devices, {})

    def test_windows_refused(self) -> None:
        """A sandbox of a Windows base takes no share."""
        self.settings = dataclasses.replace(
            self.settings,
            windows=WindowsSettings("/firmware", 4096, {"win11": self.scratch}, "sbx-base"),
        )
        self.backend.add("w", expires=NOW + 60, base="win11")
        self.paths.sandbox("w").mkdir(parents=True)
        with self.assertRaises(SbxError) as refused:
            self.shares().attach("w", "shared")
        self.assertEqual(refused.exception.code, "unsupported-guest")
        self.assertEqual(self.backend.devices, {})

    def test_detach(self) -> None:
        """Detach waits for the guest to release the device; a held device is an error."""
        self.add_running("s")
        self.shares().attach("s", "docs")
        detached = self.shares().detach("s", "docs")
        self.assertEqual(
            (detached.attached, detached.read_only, detached.host_path),
            (False, True, str(self.docs)),
        )
        self.assertEqual(self.slept, [0.5, 0.5])
        with self.assertRaises(SbxError) as refused:
            self.shares().detach("s", "docs")
        self.assertEqual(refused.exception.code, "not-attached")
        self.shares().attach("s", "shared")
        self.backend.linger = None
        with self.assertRaises(SbxError) as refused:
            self.shares().detach("s", "shared")
        self.assertEqual(refused.exception.code, "detach-pending")

    def test_mount_commands(self) -> None:
        """The guest mounts a read-only share with -o ro, and --no-mount runs nothing."""
        self.add_running("s")
        self.shares().attach("s", "shared")
        self.shares().attach("s", "docs")
        self.assertEqual(
            self.backend.guest_commands,
            [
                ["sh", "-c", "mkdir -p /mnt/shared && mount -t virtiofs shared /mnt/shared"],
                ["sh", "-c", "mkdir -p /mnt/docs && mount -t virtiofs -o ro docs /mnt/docs"],
            ],
        )
        self.add_running("t")
        result, _ = dispatch(
            self.sandboxes(), "share", "attach", "--json", "t", "shared", "--no-mount"
        )
        document = cast("dict[str, object]", result)
        self.assertEqual((document["attached"], document["mounted"]), (True, False))
        self.assertNotIn("mount_error", document)
        self.assertEqual(len(self.backend.guest_commands), 2)

    def test_mount_waits_for_the_device(self) -> None:
        """A mount that fails until the guest probes the new device is retried."""
        self.add_running("s")
        self.backend.unprobed = 2
        self.assertTrue(self.shares().attach("s", "docs").as_json()["mounted"])
        self.assertEqual(self.slept, [0.5, 0.5])

    def test_failed_mount_keeps_the_share(self) -> None:
        """A mount the guest refuses leaves the device attached and reports why."""
        self.add_running("s")
        self.backend.mount_fails = True
        document = self.shares().attach("s", "docs").as_json()
        self.assertEqual((document["attached"], document["mounted"]), (True, False))
        self.assertIn("unknown filesystem type", str(document["mount_error"]))
        self.assertEqual(self.now, MOUNT_WAIT)
        self.assertIn("docs", attached(self.backend.live_xml("sbx-s")))
        self.backend.silent = True
        document = self.shares().attach("s", "shared").as_json()
        self.assertEqual((document["attached"], document["mounted"]), (True, False))
        self.assertIn("not responding", str(document["mount_error"]))
        self.assertIn("shared", attached(self.backend.live_xml("sbx-s")))

    def test_detach_unmounts_first(self) -> None:
        """Detach unmounts every mount of the tag, topmost first, and leaves none behind."""
        self.add_running("s")
        self.shares().attach("s", "shared")
        self.backend.mounts["shared"].append("/srv/again")
        self.backend.guest_commands.clear()
        document = self.shares().detach("s", "shared").as_json()
        self.assertEqual(
            self.backend.guest_commands,
            [
                ["findmnt", "-t", "virtiofs", "-S", "shared", "-o", "TARGET", "-n", "-r"],
                ["umount", "/srv/again"],
                ["umount", "/mnt/shared"],
            ],
        )
        self.assertEqual(
            (document["guest_unmounted"], document["unmounted"]),
            (True, ["/srv/again", "/mnt/shared"]),
        )
        self.assertNotIn("recovery_command", document)
        self.assertEqual(self.backend.mounts["shared"], [])

    def test_busy_detach(self) -> None:
        """A busy mount refuses and keeps the share; --force unmounts it lazily."""
        self.add_running("s")
        self.shares().attach("s", "shared")
        self.backend.busy.add("/mnt/shared")
        with self.assertRaises(SbxError) as refused:
            self.shares().detach("s", "shared")
        self.assertEqual(refused.exception.code, "share-busy")
        self.assertIn("shared", attached(self.backend.live_xml("sbx-s")))
        self.backend.guest_commands.clear()
        result, _ = dispatch(
            self.sandboxes(), "share", "detach", "--json", "s", "shared", "--force"
        )
        self.assertEqual(self.backend.guest_commands[-1], ["umount", "-l", "/mnt/shared"])
        self.assertTrue(cast("dict[str, object]", result)["guest_unmounted"])
        self.assertNotIn("shared", attached(self.backend.live_xml("sbx-s")))

    def test_silent_guest_still_detaches(self) -> None:
        """A guest that does not answer loses the device and the result says how to recover."""
        self.add_running("s")
        self.shares().attach("s", "docs")
        self.backend.silent = True
        document = self.shares().detach("s", "docs").as_json()
        self.assertEqual((document["attached"], document["guest_unmounted"]), (False, False))
        self.assertEqual(
            document["recovery_command"],
            "sbx exec s -- sh -c 'findmnt -t virtiofs -S docs -o TARGET -n -r"
            " | xargs -r umount -l'",
        )
        self.assertNotIn("docs", attached(self.backend.live_xml("sbx-s")))

    def test_malformed_replies(self) -> None:
        """A guest that answers garbage neither fails attach nor keeps a share past detach."""
        self.add_running("s")
        self.backend.garbled = True
        document = self.shares().attach("s", "docs").as_json()
        self.assertEqual((document["attached"], document["mounted"]), (True, False))
        self.assertIn("pid is not an integer", str(document["mount_error"]))
        for force in (False, True):
            self.shares().attach("s", "shared", mount=False)
            document = self.shares().detach("s", "shared", force=force).as_json()
            self.assertEqual((document["attached"], document["guest_unmounted"]), (False, False))
            self.assertNotIn("shared", attached(self.backend.live_xml("sbx-s")))

    def test_guest_mount_lists_are_bounded(self) -> None:
        """Too many mounts, or umounts that outlast the phase, leave the guest to recovery."""
        self.add_running("s")
        self.shares().attach("s", "shared")
        self.backend.mounts["shared"] += [f"/srv/{index}" for index in range(MAX_TARGETS)]
        self.backend.guest_commands.clear()
        document = self.shares().detach("s", "shared").as_json()
        self.assertEqual((document["guest_unmounted"], document["unmounted"]), (False, []))
        self.assertEqual([argv[0] for argv in self.backend.guest_commands], ["findmnt"])
        self.shares().attach("s", "docs")
        self.backend.mounts["docs"].append("/srv/again")
        real = self.backend.agent

        def slow(domain: str, command: dict[str, object], timeout: int) -> dict[str, Any]:
            self.now += UNMOUNT_WAIT / 2
            return real(domain, command, timeout)

        with mock.patch.object(self.backend, "agent", side_effect=slow):
            document = self.shares().detach("s", "docs").as_json()
        self.assertFalse(document["guest_unmounted"])
        self.assertEqual(document["unmounted"], ["/srv/again"])

    def test_guest_targets_are_printable(self) -> None:
        """A mountpoint the guest names with control characters reaches no terminal raw."""
        self.add_running("s")
        self.shares().attach("s", "docs", mount=False)
        self.backend.mounts["docs"] = ["/mnt/\\x1b[31mred"]
        self.backend.busy.add("/mnt/\x1b[31mred")
        with self.assertRaises(SbxError) as refused:
            self.shares().detach("s", "docs")
        self.assertEqual(refused.exception.code, "share-busy")
        self.assertNotIn("\x1b", str(refused.exception))
        self.assertIn("/mnt/ [31mred", str(refused.exception))

    def test_info_lists_shares(self) -> None:
        """`info` lists each held share, with a mountpoint only where the guest mounted it."""
        self.add_running("s")
        self.shares().attach("s", "shared")
        self.shares().attach("s", "docs", mount=False)
        result, _ = dispatch(self.sandboxes(), "info", "--json", "s")
        self.assertEqual(
            cast("dict[str, object]", result)["shares"],
            [
                {
                    "tag": "shared",
                    "read_only": False,
                    "host_path": str(self.paths.sandbox("s").resolve() / "shared"),
                    "mountpoint": "/mnt/shared",
                },
                {"tag": "docs", "read_only": True, "host_path": str(self.docs)},
            ],
        )
        self.backend.silent = True
        result, _ = dispatch(self.sandboxes(), "info", "--json", "s")
        shares = cast("list[dict[str, object]]", cast("dict[str, object]", result)["shares"])
        self.assertEqual([share.get("mountpoint") for share in shares], [None, None])

    def test_detach_saved(self) -> None:
        """A saved sandbox brings its shares back at restore, so detach refuses it."""
        self.backend.add("z", expires=NOW + 60, active=False, managed_save=True)
        with self.assertRaises(SbxError) as refused:
            self.shares().detach("z", "shared")
        self.assertEqual(refused.exception.code, "saved")

    def test_disk_cap(self) -> None:
        """Past the cap, shared refuses to attach and gc detaches it; read-only shares stay."""
        self.add_running("s")
        self.add_running("t")
        shares = self.shares()
        shares.attach("s", "shared")
        shares.attach("s", "docs")
        shares.attach("t", "docs")
        self.settings = dataclasses.replace(self.settings, disk_cap_bytes=0)
        (self.paths.sandbox("s") / "shared" / "fill").write_bytes(b"x" * 8192)
        with self.assertRaises(SbxError) as refused:
            self.shares().attach("t", "shared")
        self.assertEqual(refused.exception.code, "disk-full")
        self.assertEqual([action.name for action in self.shares().reclaim(dry_run=True)], ["s"])
        self.assertIn("shared", attached(self.backend.live_xml("sbx-s")))
        self.backend.linger = 0
        with mock.patch.object(Sandboxes, "host_synced", return_value=True):
            result, _ = dispatch(self.sandboxes(), "gc", "--json")
        self.assertEqual([action["name"] for action in cast("list[dict[str, str]]", result)], ["s"])
        self.assertEqual(set(attached(self.backend.live_xml("sbx-s"))), {"docs"})
        self.assertEqual(set(attached(self.backend.live_xml("sbx-t"))), {"docs"})

    def test_reclaim_continues_past_a_held_share(self) -> None:
        """A guest that keeps shared is reported, and the next sandbox still loses it."""
        self.add_running("s")
        self.add_running("t")
        for name in ("s", "t"):
            self.shares().attach(name, "shared")
        self.settings = dataclasses.replace(self.settings, disk_cap_bytes=0)
        (self.paths.sandbox("s") / "shared" / "fill").write_bytes(b"x" * 8192)
        self.backend.stuck.add("sbx-s")
        actions = self.shares().reclaim(dry_run=False)
        self.assertEqual([action.name for action in actions], ["s", "t"])
        self.assertIn("detach-pending", actions[0].reason)
        self.assertNotIn("shared", attached(self.backend.live_xml("sbx-t")))

    def test_reclaim_skips_a_vanished_sandbox(self) -> None:
        """A domain another client removes mid-reclaim is skipped, before or after its lookup."""
        for name in ("s", "t", "u"):
            self.add_running(name)
            self.shares().attach(name, "shared")
        self.settings = dataclasses.replace(self.settings, disk_cap_bytes=0)
        (self.paths.sandbox("s") / "shared" / "fill").write_bytes(b"x" * 8192)
        self.backend.vanished.add("sbx-s")
        self.backend.linger = 0
        real = self.backend.live_xml

        def vanish_t(domain: str) -> str:
            xml = real(domain)
            if domain == "sbx-t":
                self.backend.vanished.add(domain)
            return xml

        with mock.patch.object(self.backend, "live_xml", side_effect=vanish_t):
            actions = self.shares().reclaim(dry_run=False)
        self.assertEqual([action.name for action in actions], ["u"])

    def test_command_line(self) -> None:
        """`share attach` returns the share's JSON form."""
        self.add_running("s")
        result, code = dispatch(self.sandboxes(), "share", "attach", "--json", "s", "shared")
        self.assertEqual((code, cast("dict[str, object]", result)["attached"]), (0, True))


if __name__ == "__main__":
    unittest.main()
