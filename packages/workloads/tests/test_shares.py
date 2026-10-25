# Copyright (c) 2026 Bad3r
"""Runtime shares in workload-grantd: policy lookup, decisions, and virsh commands."""

import unittest
from typing import TYPE_CHECKING, cast

from workloads.grantd import LiveShare, Virsh
from workloads.grants import GrantError, Record

from tests.test_grantd import Harness, code

if TYPE_CHECKING:
    from collections.abc import Sequence

LATE = "/etc/workloads/shares/dev/late.xml"
DOMAIN_XML = """<domain><devices>
  <filesystem type='mount'><driver type='virtiofs'/><target dir='late'/><alias name='fs1'/>
    <readonly/></filesystem>
  <filesystem type='mount'><driver type='path'/><target dir='ninep'/></filesystem>
  <disk type='file'><target dev='vda'/></disk>
</devices></domain>"""


def share(harness: Harness, verb: str, guest: str = "dev", tag: str = "late") -> Record:
    """Send one share request."""
    return harness.ask({"verb": f"share-{verb}", "guest": guest, "share": tag})


class ShareTest(unittest.TestCase):
    """Attach and detach run under the lock after the journal records them."""

    def test_attach(self) -> None:
        """A declared share of a running guest attaches its rendered device."""
        harness = Harness()
        answer = share(harness, "attach")
        self.assertEqual(
            answer["share"],
            {
                "guest": "dev",
                "tag": "late",
                "read_only": False,
                "mount_point": "/mnt/late",
                "attached": True,
            },
        )
        self.assertEqual(
            harness.events, ["lock", "journal attached", f"attach dev {LATE}", "unlock"]
        )
        entry = harness.journal[0]
        self.assertEqual(
            (entry["guest"], entry["share"], entry["verb"]), ("dev", "late", "share-attach")
        )

    def test_attach_refusals(self) -> None:
        """An attached share, a stopped guest, Windows, and undeclared shares change nothing."""
        harness = Harness()
        harness.libvirt.live["dev"].add("late")
        self.assertEqual(code(share(harness, "attach")), "already-attached")
        harness.libvirt.states["dev"] = "paused"
        self.assertEqual(code(share(harness, "attach")), "not-running")
        self.assertEqual(code(share(harness, "attach", "win11", "isos")), "unsupported-guest")
        self.assertEqual(code(share(harness, "attach", tag="drop")), "not-declared")
        self.assertEqual(code(share(harness, "attach", guest="web")), "not-declared")
        self.assertNotIn("journal attached", harness.events)
        self.assertEqual({entry["decision"] for entry in harness.journal}, {"refused"})

    def test_detach_waits_for_release(self) -> None:
        """Detach polls until the device leaves the live definition."""
        harness = Harness()
        harness.libvirt.live["dev"].add("late")
        answer = share(harness, "detach")
        self.assertFalse(cast("Record", answer["share"])["attached"])
        self.assertEqual(
            harness.events,
            ["lock", "journal detached", "detach dev fs-late", "sleep 0.5", "sleep 0.5", "unlock"],
        )

    def test_detach_undeclared(self) -> None:
        """A live share whose declaration is gone still detaches, with its live mode."""
        harness = Harness()
        harness.libvirt.live["dev"].add("ro-old")
        answer = cast("Record", share(harness, "detach", tag="ro-old")["share"])
        self.assertEqual(
            (answer["attached"], answer["read_only"], answer["mount_point"]), (False, True, None)
        )
        self.assertIn("detach dev fs-ro-old", harness.events)

    def test_detach_fails_closed(self) -> None:
        """A device the guest never releases is an error, not a success."""
        harness = Harness()
        harness.libvirt.live["dev"].add("late")
        harness.libvirt.linger = None
        answer = share(harness, "detach")
        self.assertEqual(code(answer), "detach-pending")
        self.assertEqual(harness.journal[-1]["decision"], "failed")

    def test_detach_refusals(self) -> None:
        """Nothing attached, no such guest, or a saved guest whose restore brings the share back."""
        harness = Harness()
        self.assertEqual(code(share(harness, "detach")), "not-attached")
        self.assertEqual(code(share(harness, "detach", tag="drop")), "not-attached")
        self.assertEqual(code(share(harness, "detach", guest="web")), "not-declared")
        self.assertEqual(code(share(harness, "detach", "win11", "isos")), "unsupported-guest")
        harness.libvirt.states["dev"] = "shut off"
        self.assertEqual(code(share(harness, "detach")), "not-attached")
        harness.libvirt.saved_domains.add("dev")
        self.assertEqual(code(share(harness, "detach")), "saved")
        self.assertEqual(
            [event for event in harness.events if event.startswith(("attach", "detach"))], []
        )

    def test_grammar(self) -> None:
        """Share requests take exactly a guest and a share."""
        harness = Harness()
        for request in [
            {"verb": "share-attach", "guest": "dev"},
            {"verb": "share-detach", "guest": "dev", "share": "late", "ttl": 60},
            {"verb": "share-attach", "guest": 1, "share": "late"},
        ]:
            self.assertEqual(code(harness.ask(request)), "invalid-request", request)


class Runner:
    """Answers virsh by its subcommand and keeps every call."""

    def __init__(self, answers: dict[str, tuple[int, str, str]]) -> None:
        """Answers keyed by the subcommand."""
        self.answers = answers
        self.calls: list[list[str]] = []

    def __call__(self, argv: Sequence[str], stdin: str | None) -> tuple[int, str, str]:
        """Record and answer."""
        del stdin
        self.calls.append(list(argv))
        return self.answers.get(argv[3], (0, "", ""))


class VirshTest(unittest.TestCase):
    """The commands the libvirt adapter runs and the output it parses."""

    def test_commands(self) -> None:
        """Every call names the system URI; attach and detach act on the live guest only."""
        runner = Runner(
            {
                "domstate": (0, "running\n\n", ""),
                "dominfo": (0, "Name:           dev\nManaged save:   yes\n", ""),
                "dumpxml": (0, DOMAIN_XML, ""),
            }
        )
        virsh = Virsh("/virsh", runner)
        self.assertEqual(virsh.state("dev"), "running")
        self.assertTrue(virsh.saved("dev"))
        self.assertEqual(virsh.shares("dev"), {"late": LiveShare("fs1", read_only=True)})
        virsh.attach("dev", LATE)
        virsh.detach("dev", "fs1")
        self.assertEqual(
            runner.calls[-2:],
            [
                ["/virsh", "-c", "qemu:///system", "attach-device", "dev", LATE, "--live"],
                ["/virsh", "-c", "qemu:///system", "detach-device-alias", "dev", "fs1", "--live"],
            ],
        )

    def test_failures(self) -> None:
        """Failed virsh calls and unparsable output fail with the libvirt code."""
        failing = Virsh("/virsh", Runner({"attach-device": (1, "", "error: no free slot")}))
        with self.assertRaisesRegex(GrantError, "no free slot") as caught:
            failing.attach("dev", LATE)
        self.assertEqual(caught.exception.code, "libvirt")
        garbled = Virsh("/virsh", Runner({"dumpxml": (0, "<domain", ""), "dominfo": (0, "", "")}))
        for call in (lambda: garbled.shares("dev"), lambda: garbled.saved("dev")):
            with self.assertRaises(GrantError) as caught:
                call()
            self.assertEqual(caught.exception.code, "libvirt")


if __name__ == "__main__":
    unittest.main()
