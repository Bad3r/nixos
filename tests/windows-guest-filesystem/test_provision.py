# Copyright (c) 2026 Bad3r
# /// script
# requires-python = ">=3.14"
# dependencies = []
# ///
# ruff: noqa: S101, PT009, PT027
"""Exercise convergence and failure paths without connecting to a Windows VM."""

from __future__ import annotations

import base64
import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "provision", REPO / "scripts/windows-guest/provision.py"
)
assert SPEC is not None
assert SPEC.loader is not None
provision = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(provision)

COMMANDS = [
    "guest-exec",
    "guest-exec-status",
    "guest-file-open",
    "guest-file-write",
    "guest-file-close",
]
ROOT = r"C:\Program Files\NixOS\VirtioFS"
XML = """<domain><devices><filesystem><driver type='virtiofs'/>
<source dir='/mnt/outlook'/><target dir='transfer'/>
</filesystem></devices></domain>"""


class ReconcileTests(unittest.TestCase):
    """Ensure an inspection result controls every guest mutation."""

    def setUp(self) -> None:
        """Supply small local payloads and a fully observable fake agent."""
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        directory = Path(self.temporary.name)
        self.payload = directory / "payload"
        self.payload.write_bytes(b"\x00\xffdriver")
        self.script = directory / "script.ps1"
        self.script.write_text("exit 0")
        self.stamp = directory / "converged"
        self.config_path = Path("/nix/store/0-windows-guest-filesystem.json")
        self.config = {
            "stamp": str(self.stamp),
            "transfer_dir": "/mnt/outlook",
            "winfsp_version": "2.1.25156",
            "files": {
                "virtiofs.exe": str(self.payload),
            },
            "script": str(self.script),
        }
        self.agent = unittest.mock.create_autospec(provision.Agent, instance=True)
        self.agent.domain = "RDPWindows"
        self.agent.virsh.side_effect = ["5", "running", XML]
        self.agent.request.return_value = {
            "supported_commands": [{"name": command, "enabled": True} for command in COMMANDS]
        }
        self.agent.powershell.side_effect = [
            (0, ROOT),
            (0, "ready"),
        ]

    def test_offline_guest_is_not_started(self) -> None:
        """An inactive domain requires no agent request or guest write."""
        self.agent.virsh.side_effect = ["-"]
        provision.reconcile(self.config, self.agent, self.config_path)
        self.agent.request.assert_not_called()
        self.agent.write_file.assert_not_called()
        self.agent.powershell.assert_not_called()

    def test_offline_guest_clears_stamp(self) -> None:
        """A stopped guest forgets its check, so a reused domain ID cannot skip one."""
        self.stamp.write_text(f"5 {self.config_path}\n")
        self.agent.virsh.side_effect = ["-"]
        provision.reconcile(self.config, self.agent, self.config_path)
        self.assertFalse(self.stamp.exists())

    def test_paused_guest_is_deferred(self) -> None:
        """A guest that holds a domain ID but is not running receives no agent request."""
        self.agent.virsh.side_effect = ["5", "paused"]
        provision.reconcile(self.config, self.agent, self.config_path)
        self.agent.request.assert_not_called()
        self.assertFalse(self.stamp.exists())

    def test_converged_run_writes_stamp(self) -> None:
        """A run whose steps all succeed records the domain ID and the declaration."""
        provision.reconcile(self.config, self.agent, self.config_path)
        self.assertEqual(self.stamp.read_text(), f"5 {self.config_path}\n")

    def test_matching_stamp_skips_guest_calls(self) -> None:
        """A checked guest start costs one virsh call and nothing in the guest."""
        self.stamp.write_text(f"5 {self.config_path}\n")
        provision.reconcile(self.config, self.agent, self.config_path)
        self.assertEqual(self.agent.virsh.call_count, 1)
        self.agent.request.assert_not_called()
        self.agent.write_file.assert_not_called()
        self.agent.powershell.assert_not_called()

    def test_new_guest_start_forces_full_run(self) -> None:
        """A domain ID from an earlier start does not cover the running guest."""
        self.stamp.write_text(f"4 {self.config_path}\n")
        provision.reconcile(self.config, self.agent, self.config_path)
        self.agent.request.assert_called_once_with("guest-info")
        self.assertEqual(self.stamp.read_text(), f"5 {self.config_path}\n")

    def test_changed_declaration_forces_full_run(self) -> None:
        """A switch to another manifest checks the running guest again."""
        self.stamp.write_text("5 /nix/store/1-windows-guest-filesystem.json\n")
        provision.reconcile(self.config, self.agent, self.config_path)
        self.agent.request.assert_called_once_with("guest-info")
        self.assertEqual(self.stamp.read_text(), f"5 {self.config_path}\n")

    def test_failed_run_writes_no_stamp(self) -> None:
        """A failed step leaves no stamp, so the next timer run checks again."""
        self.agent.powershell.side_effect = [
            (0, ROOT),
            (10, "needs setup"),
            (1, "installer failed"),
        ]
        with self.assertRaisesRegex(RuntimeError, "installer failed"):
            provision.reconcile(self.config, self.agent, self.config_path)
        self.assertFalse(self.stamp.exists())

    def test_failed_check_leaves_no_stamp_for_a_rollback(self) -> None:
        """A failed check of a new declaration cannot let a rollback skip the guest."""
        previous = Path("/nix/store/1-windows-guest-filesystem.json")
        self.stamp.write_text(f"5 {previous}\n")
        self.agent.virsh.side_effect = ["5", "running", XML, "5", "running", XML]
        self.agent.powershell.side_effect = [
            (0, ROOT),
            (1, "occupied"),
            (0, ROOT),
            (0, "ready"),
        ]
        with self.assertRaisesRegex(RuntimeError, "occupied"):
            provision.reconcile(self.config, self.agent, self.config_path)
        self.assertFalse(self.stamp.exists())
        provision.reconcile(self.config, self.agent, previous)
        self.assertEqual(self.agent.request.call_count, 2)
        self.assertEqual(self.stamp.read_text(), f"5 {previous}\n")

    def test_missing_live_filesystem_requires_power_cycle(self) -> None:
        """A stale active XML fails the filesystem step before any installer reaches the guest."""
        self.agent.virsh.side_effect = ["5", "running", "<domain><devices/></domain>"]
        with self.assertRaisesRegex(RuntimeError, "^filesystem: .*fully shut Windows down"):
            provision.reconcile(self.config, self.agent, self.config_path)
        destinations = [call.args[0] for call in self.agent.write_file.call_args_list]
        self.assertNotIn(ROOT + r"\staging\virtiofs.exe", destinations)
        calls = [call.args[0] for call in self.agent.powershell.call_args_list]
        self.assertFalse(any("shared-folder.ps1" in call for call in calls))

    def test_disabled_command_fails_before_upload(self) -> None:
        """Do not start setup through a partially enabled guest agent."""
        self.agent.request.return_value = {"supported_commands": []}
        with self.assertRaisesRegex(RuntimeError, "guest-file-write"):
            provision.reconcile(self.config, self.agent, self.config_path)
        self.agent.write_file.assert_not_called()

    def test_ready_guest_does_not_receive_installers(self) -> None:
        """A ready guest receives the scripts and no installer payload or Apply run."""
        provision.reconcile(self.config, self.agent, self.config_path)
        destinations = [call.args[0] for call in self.agent.write_file.call_args_list]
        self.assertEqual(
            destinations,
            [
                ROOT + r"\staging\manifest.json",
                ROOT + r"\staging\shared-folder.ps1",
            ],
        )
        calls = [call.args[0] for call in self.agent.powershell.call_args_list]
        self.assertFalse(any(call.endswith("Apply; exit $LASTEXITCODE") for call in calls))

    def test_apply_transfers_binary_bytes_only_to_staging(self) -> None:
        """An executable update must not overwrite the running service binary."""
        self.agent.powershell.side_effect = [
            (0, ROOT),
            (10, "needs setup"),
            (0, "ready"),
        ]
        provision.reconcile(self.config, self.agent, self.config_path)
        self.agent.write_file.assert_any_call(
            ROOT + r"\staging\virtiofs.exe", self.payload.read_bytes()
        )
        calls = [call.args[0] for call in self.agent.powershell.call_args_list]
        self.assertTrue(
            any(
                "shared-folder.ps1" in call and call.endswith("Apply; exit $LASTEXITCODE")
                for call in calls
            )
        )

    def test_probe_failure_is_not_treated_as_install_request(self) -> None:
        """A collision, reboot requirement or exception must remain a failure."""
        self.agent.powershell.side_effect = [
            (0, ROOT),
            (1, "occupied"),
        ]
        with self.assertRaisesRegex(RuntimeError, "^filesystem: .*occupied$"):
            provision.reconcile(self.config, self.agent, self.config_path)
        destinations = [call.args[0] for call in self.agent.write_file.call_args_list]
        self.assertNotIn(ROOT + r"\staging\virtiofs.exe", destinations)
        calls = [call.args[0] for call in self.agent.powershell.call_args_list]
        self.assertFalse(any(call.endswith("Apply; exit $LASTEXITCODE") for call in calls))


class ProtocolTests(unittest.TestCase):
    """Protect transfer accounting and asynchronous command semantics."""

    def test_short_writes_preserve_every_byte(self) -> None:
        """Advance by acknowledged bytes rather than assuming a full write."""
        agent = provision.Agent("virsh", "qemu:///system", "RDPWindows")
        with patch.object(
            agent, "request", side_effect=[7, {"count": 2}, {"count": 3}, {}]
        ) as request:
            agent.write_file(r"C:\payload", b"abcde")
        writes = [
            call.args[1]["buf-b64"]
            for call in request.call_args_list
            if call.args[0] == "guest-file-write"
        ]
        self.assertEqual([base64.b64decode(value) for value in writes], [b"abcde", b"cde"])
        self.assertEqual(request.call_args.args, ("guest-file-close", {"handle": 7}))

    def test_zero_write_fails_and_closes_handle(self) -> None:
        """A stalled transfer cannot spin forever or appear successful."""
        agent = provision.Agent("virsh", "qemu:///system", "RDPWindows")
        with (
            patch.object(agent, "request", side_effect=[7, {"count": 0}, {}]) as request,
            self.assertRaisesRegex(RuntimeError, "Invalid guest write count"),
        ):
            agent.write_file(r"C:\payload", b"data")
        self.assertEqual(request.call_args.args, ("guest-file-close", {"handle": 7}))

    def test_process_is_submitted_once_and_failure_is_returned(self) -> None:
        """Polling must preserve stderr and the process exit code."""
        agent = provision.Agent("virsh", "qemu:///system", "RDPWindows")
        responses = [
            {"pid": 42},
            {"exited": False},
            {"exited": True, "exitcode": 1, "err-data": "ZmFpbGVk"},
        ]
        with (
            patch.object(agent, "request", side_effect=responses) as request,
            patch.object(provision.time, "sleep"),
        ):
            self.assertEqual(agent.powershell("exit 1"), (1, "failed"))
        self.assertEqual([call.args[0] for call in request.call_args_list].count("guest-exec"), 1)

    def test_execution_timeout_does_not_resubmit(self) -> None:
        """A timeout leaves a diagnostic identifying the uncertain process."""
        agent = provision.Agent("virsh", "qemu:///system", "RDPWindows")
        with (
            patch.object(agent, "request", return_value={"pid": 42}) as request,
            self.assertRaisesRegex(TimeoutError, "PID 42"),
        ):
            agent.powershell("exit 0", timeout=0)
        self.assertEqual(request.call_count, 1)


class WindowsScriptTests(unittest.TestCase):
    """Run the actual PowerShell script against Windows API fixtures."""

    def run_case(self, case: str, mode: str = "Probe") -> subprocess.CompletedProcess[str]:
        """Use PowerShell's parser and command dispatch without native installs."""
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "staging/manifest.json"
            manifest.parent.mkdir()
            manifest.write_text(
                json.dumps(
                    {
                        "winfsp_version": "2.1.25156",
                        "hashes": {
                            name: name
                            for name in (
                                "winfsp.msi",
                                "viofs.inf",
                                "viofs.cat",
                                "viofs.sys",
                                "virtiofs.exe",
                            )
                        },
                    }
                )
            )
            return subprocess.run(
                [
                    "pwsh",
                    "-NoLogo",
                    "-NoProfile",
                    "-NonInteractive",
                    "-File",
                    str(REPO / "tests/windows-guest-filesystem/mock-windows.ps1"),
                    str(REPO / "scripts/windows-guest/shared-folder.ps1"),
                    str(manifest),
                    case,
                    mode,
                ],
                capture_output=True,
                text=True,
                check=False,
                timeout=30,
            )

    def test_ready_probe_is_read_only(self) -> None:
        """Any install or service mutation in the ready path fails the fixture."""
        result = self.run_case("ready")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Windows filesystem ready", result.stdout)

    def test_missing_components_request_apply(self) -> None:
        """An incomplete setup returns the host's designated convergence code."""
        result = self.run_case("new")
        self.assertEqual(result.returncode, 10, result.stderr)

    def test_new_install_converges(self) -> None:
        """Install Core, bind the driver, create the service and verify its mount."""
        result = self.run_case("new", "Apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Windows filesystem ready", result.stdout)

    def test_owner_override_is_removed(self) -> None:
        """Changing a service setting must restore automatic ownership."""
        result = self.run_case("owner", "Apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("removed Owner", result.stdout)

    def test_drive_collision_is_not_overwritten(self) -> None:
        """An unrelated T: volume stops reconciliation before installation."""
        result = self.run_case("collision", "Apply")
        self.assertEqual(result.returncode, 1)
        self.assertIn("occupied", result.stderr)

    def test_installer_failure_surfaces(self) -> None:
        """A native installer failure must not be replaced by a ready result."""
        result = self.run_case("install-failure", "Apply")
        self.assertEqual(result.returncode, 1)
        self.assertIn("exit code 1618", result.stderr)

    def test_reboot_requirement_is_recorded_without_restarting(self) -> None:
        """A successful installation needing reboot remains visibly pending."""
        result = self.run_case("reboot", "Apply")
        self.assertEqual(result.returncode, 1)
        self.assertIn("PendingRebootBootTime", result.stdout)
        self.assertIn("needs a guest restart", result.stderr)

    def test_pending_reboot_does_not_reinstall(self) -> None:
        """Repeated runs wait for the requested restart instead of rerunning MSI."""
        result = self.run_case("pending-reboot", "Apply")
        self.assertEqual(result.returncode, 1)
        self.assertIn("waiting for a guest restart", result.stderr)

    def test_hash_mismatch_prevents_installation(self) -> None:
        """Delivery corruption must fail before an installer executes."""
        result = self.run_case("bad-hash", "Apply")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Payload hash mismatch", result.stderr)


if __name__ == "__main__":
    unittest.main()
