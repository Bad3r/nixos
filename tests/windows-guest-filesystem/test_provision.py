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
        self.firewall_script = directory / "guest-services-firewall.ps1"
        self.firewall_script.write_text("exit 0")
        self.config = {
            "transfer_dir": "/mnt/outlook",
            "winfsp_version": "2.1.25156",
            "files": {
                "virtiofs.exe": str(self.payload),
                "pin-quick-access.ps1": str(self.script),
            },
            "script": str(self.script),
            "guest_services_firewall_script": str(self.firewall_script),
            "quick_access_script": str(self.script),
        }
        self.agent = unittest.mock.create_autospec(provision.Agent, instance=True)
        self.agent.domain = "RDPWindows"
        self.agent.virsh.side_effect = ["running", XML]
        self.agent.request.return_value = {
            "supported_commands": [{"name": command, "enabled": True} for command in COMMANDS]
        }
        self.agent.powershell.side_effect = [
            (0, ROOT),
            (0, "firewall ready"),
            (0, "ready"),
            (0, "pinned"),
        ]

    def test_offline_guest_is_not_started(self) -> None:
        """An inactive domain requires no agent request or guest write."""
        self.agent.virsh.side_effect = ["shut off"]
        provision.reconcile(self.config, self.agent)
        self.agent.request.assert_not_called()
        self.agent.write_file.assert_not_called()
        self.agent.powershell.assert_not_called()

    def test_missing_live_filesystem_requires_power_cycle(self) -> None:
        """A stale active XML must fail before installing anything."""
        self.agent.virsh.side_effect = ["running", "<domain><devices/></domain>"]
        with self.assertRaisesRegex(RuntimeError, "fully shut Windows down"):
            provision.reconcile(self.config, self.agent)
        self.agent.request.assert_not_called()

    def test_disabled_command_fails_before_upload(self) -> None:
        """Do not start setup through a partially enabled guest agent."""
        self.agent.request.return_value = {"supported_commands": []}
        with self.assertRaisesRegex(RuntimeError, "guest-file-write"):
            provision.reconcile(self.config, self.agent)
        self.agent.write_file.assert_not_called()

    def test_ready_guest_does_not_receive_installers(self) -> None:
        """A mounted drive refreshes Quick access without reinstalling Windows files."""
        provision.reconcile(self.config, self.agent)
        destinations = [call.args[0] for call in self.agent.write_file.call_args_list]
        self.assertEqual(
            destinations,
            [
                ROOT + r"\staging\manifest.json",
                ROOT + r"\staging\shared-folder.ps1",
                ROOT + r"\staging\guest-services-firewall.ps1",
                ROOT + r"\staging\pin-quick-access.ps1",
                ROOT + r"\staging\quick-access.ps1",
            ],
        )
        self.assertEqual(self.agent.powershell.call_count, 4)

    def test_apply_transfers_binary_bytes_only_to_staging(self) -> None:
        """An executable update must not overwrite the running service binary."""
        self.agent.powershell.side_effect = [
            (0, ROOT),
            (10, "firewall setup needed"),
            (0, "firewall ready"),
            (10, "needs setup"),
            (0, "ready"),
            (0, "pinned"),
        ]
        provision.reconcile(self.config, self.agent)
        self.agent.write_file.assert_any_call(
            ROOT + r"\staging\virtiofs.exe", self.payload.read_bytes()
        )
        self.assertTrue(
            self.agent.powershell.call_args_list[4].args[0].endswith("Apply; exit $LASTEXITCODE")
        )

    def test_guest_firewall_is_reconciled_before_filesystem_setup(self) -> None:
        """A missing managed service rule is applied before filesystem work continues."""
        self.agent.powershell.side_effect = [
            (0, ROOT),
            (10, "rule missing"),
            (0, "firewall ready"),
            (0, "ready"),
            (0, "pinned"),
        ]
        provision.reconcile(self.config, self.agent)
        calls = [call.args[0] for call in self.agent.powershell.call_args_list]
        self.assertIn("guest-services-firewall.ps1", calls[1])
        self.assertTrue(calls[1].endswith("Probe; exit $LASTEXITCODE"))
        self.assertTrue(calls[2].endswith("Apply; exit $LASTEXITCODE"))
        self.assertIn("shared-folder.ps1", calls[3])

    def test_guest_firewall_probe_failure_surfaces(self) -> None:
        """A policy error stops the timer with its guest diagnostic intact."""
        self.agent.powershell.side_effect = [(0, ROOT), (1, "firewall query failed")]
        with self.assertRaisesRegex(
            RuntimeError, "Windows guest firewall probe failed.*query failed"
        ):
            provision.reconcile(self.config, self.agent)
        self.assertEqual(self.agent.powershell.call_count, 2)
        self.assertEqual(self.agent.write_file.call_count, 3)

    def test_pin_failure_surfaces_without_reinstalling_filesystem(self) -> None:
        """A failed user-session task remains visible in the host service result."""
        self.agent.powershell.side_effect = [
            (0, ROOT),
            (0, "firewall ready"),
            (0, "ready"),
            (1, "pin failed"),
        ]
        with self.assertRaisesRegex(RuntimeError, "pin failed"):
            provision.reconcile(self.config, self.agent)
        self.assertFalse(
            any("-Mode Apply" in call.args[0] for call in self.agent.powershell.call_args_list)
        )

    def test_probe_failure_is_not_treated_as_install_request(self) -> None:
        """A collision, reboot requirement or exception must remain a failure."""
        self.agent.powershell.side_effect = [
            (0, ROOT),
            (0, "firewall ready"),
            (1, "occupied"),
        ]
        with self.assertRaisesRegex(RuntimeError, "occupied"):
            provision.reconcile(self.config, self.agent)
        self.assertEqual(self.agent.write_file.call_count, 3)


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


class GuestServicesFirewallTests(unittest.TestCase):
    """Exercise the guest firewall policy without touching a Windows host."""

    def run_case(self, case: str, mode: str = "Probe") -> subprocess.CompletedProcess[str]:
        """Run the production policy against an isolated NetSecurity fixture."""
        return subprocess.run(
            [
                "pwsh",
                "-NoLogo",
                "-NoProfile",
                "-NonInteractive",
                "-File",
                str(REPO / "tests/windows-guest-filesystem/mock-guest-firewall.ps1"),
                str(REPO / "scripts/windows-guest/guest-services-firewall.ps1"),
                case,
                mode,
            ],
            capture_output=True,
            text=True,
            check=False,
            timeout=30,
        )

    def test_missing_policy_requests_apply_without_mutation(self) -> None:
        """Probe reports drift with the designated status and performs no repair."""
        result = self.run_case("missing")
        self.assertEqual(result.returncode, 10, result.stderr)
        self.assertIn("missing or differs", result.stdout)

    def test_ready_policy_probe_is_read_only(self) -> None:
        """The intended port and subnet pass without replacing the existing rule."""
        result = self.run_case("ready")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("TCP 8000-9999 from 10.11.11.0/24", result.stdout)

    def test_missing_policy_is_created(self) -> None:
        """Apply creates an enabled inbound TCP rule with the declared scope."""
        result = self.run_case("missing", "Apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("firewall rule created", result.stdout)
        self.assertIn("TCP 8000-9999 from 10.11.11.0/24", result.stdout)

    def test_stale_policy_is_replaced(self) -> None:
        """Apply repairs a stale protocol, port range, and remote subnet."""
        result = self.run_case("stale", "Apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("firewall rule replaced", result.stdout)
        self.assertIn("TCP 8000-9999 from 10.11.11.0/24", result.stdout)

    def test_repair_failure_is_reported(self) -> None:
        """A guest firewall API failure remains a nonzero provisioning result."""
        result = self.run_case("apply-failure", "Apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("fixture firewall operation failed", result.stderr)


class QuickAccessTests(unittest.TestCase):
    """Exercise task policy and per-user Shell pinning without a desktop."""

    def run_case(self, script: str, case: str) -> subprocess.CompletedProcess[str]:
        """Execute the production scripts against task and Shell API fixtures."""
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "staging/manifest.json"
            manifest.parent.mkdir()
            manifest.write_text(
                json.dumps({"hashes": {"pin-quick-access.ps1": "pin-quick-access.ps1"}})
            )
            return subprocess.run(
                [
                    "pwsh",
                    "-NoLogo",
                    "-NoProfile",
                    "-NonInteractive",
                    "-File",
                    str(REPO / "tests/windows-guest-filesystem/mock-quick-access.ps1"),
                    str(REPO / "scripts/windows-guest" / script),
                    str(manifest),
                    case,
                ],
                capture_output=True,
                text=True,
                check=False,
                timeout=30,
            )

    def test_new_pin_is_verified(self) -> None:
        """A new Shell entry is pinned through the canonical verb."""
        result = self.run_case("pin-quick-access.ps1", "new")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("pin invoked", result.stdout)

    def test_existing_pin_is_not_toggled_off(self) -> None:
        """An existing Quick access item must never receive the toggle verb."""
        result = self.run_case("pin-quick-access.ps1", "ready")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("pin invoked", result.stdout)

    def test_failed_shell_pin_is_reported(self) -> None:
        """Invoking a verb alone is insufficient to report a successful pin."""
        result = self.run_case("pin-quick-access.ps1", "pin-failure")
        self.assertEqual(result.returncode, 1)
        self.assertIn("was not added", result.stderr)

    def test_task_is_registered_for_interactive_users(self) -> None:
        """Registration must use the Users group with limited privileges."""
        result = self.run_case("quick-access.ps1", "new")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("task registered", result.stdout)

    def test_healthy_task_is_not_reregistered(self) -> None:
        """An unchanged policy only refreshes the user's pin."""
        result = self.run_case("quick-access.ps1", "ready")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("task registered", result.stdout)

    def test_disabled_task_is_repaired(self) -> None:
        """Policy drift must restore an enabled logon trigger."""
        result = self.run_case("quick-access.ps1", "disabled")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("task registered", result.stdout)

    def test_no_user_session_defers_pinning(self) -> None:
        """A headless guest receives the policy and waits for user logon."""
        result = self.run_case("quick-access.ps1", "no-session")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("awaits an interactive", result.stdout)

    def test_task_failure_is_reported(self) -> None:
        """A failed scheduled execution cannot become a ready result."""
        result = self.run_case("quick-access.ps1", "pin-failure")
        self.assertEqual(result.returncode, 1)
        self.assertIn("task failed", result.stderr)

    def test_already_running_task_is_awaited(self) -> None:
        """A logon-triggered pin can finish without being restarted or timing out."""
        result = self.run_case("quick-access.ps1", "already-running")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("present in File Explorer", result.stdout)

    def test_corrupt_pin_payload_is_rejected(self) -> None:
        """A hash mismatch stops task registration and execution."""
        result = self.run_case("quick-access.ps1", "bad-hash")
        self.assertEqual(result.returncode, 1)
        self.assertIn("hash mismatch", result.stderr)


if __name__ == "__main__":
    unittest.main()
