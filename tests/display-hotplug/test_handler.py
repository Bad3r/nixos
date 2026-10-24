# Copyright (c) 2026 Bad3r
# ruff: noqa: PT009, PT027
"""Exercise RandR selection and handler effects without changing a display."""

import importlib.util
import os
import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

HELPER = Path(__file__).resolve().parents[2] / "modules/apps/i3wm/_display-hotplug.py"
spec = importlib.util.spec_from_file_location("display_hotplug", HELPER)
handler = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = handler
spec.loader.exec_module(handler)

QUERY = """Screen 0: minimum 8 x 8, current 2560 x 1440, maximum 32767 x 32767
HDMI-0 disconnected primary (normal left inverted right x axis y axis)
DP-4 connected 2560x1440+0+0 (normal left inverted right x axis y axis)
   2560x1440     59.95 + 180.00   164.96   143.98*  120.00
   1920x1080    240.00    60.00
HDMI-1 connected primary 3840x2160+2560+0 (normal left inverted right x axis y axis)
   3840x2160    60.00*+  120.00
   2560x1440   240.00
DP-5 disconnected (normal left inverted right x axis y axis)
"""


class DisplayHotplugTest(unittest.TestCase):
    """Check independent output selection and observable RandR commands."""

    def run_handler(
        self,
        query: str = QUERY,
        pin: tuple[str, ...] = (),
        output: str = "DP-4",
        event: str = "connected",
        results: tuple[int, ...] = (0,),
    ) -> tuple[MagicMock, MagicMock]:
        """Run a connect event against a fake RandR server."""
        environment = {"SRANDRD_OUTPUT": output, "SRANDRD_EVENT": event}
        with (
            patch.dict(os.environ, environment),
            patch.object(sys, "argv", [str(HELPER), *pin]),
            patch.object(handler.subprocess, "check_output", return_value=query) as read,
            patch.object(
                handler.subprocess,
                "run",
                side_effect=[subprocess.CompletedProcess([], code) for code in results],
            ) as run,
        ):
            handler.main()
        return read, run

    def test_native_resolution_before_refresh(self) -> None:
        """Native resolution before refresh."""
        _, run = self.run_handler()
        run.assert_called_once_with(
            ["xrandr", "--output", "DP-4", "--mode", "2560x1440", "--rate", "180.00"], check=False
        )

    def test_each_output_has_its_own_modes(self) -> None:
        """Each output has its own modes."""
        _, run = self.run_handler(output="HDMI-1")
        run.assert_called_once_with(
            ["xrandr", "--output", "HDMI-1", "--mode", "3840x2160", "--rate", "120.00"], check=False
        )

    def test_already_selected_does_not_generate_another_event(self) -> None:
        """Already selected does not generate another event."""
        _, run = self.run_handler(
            query=QUERY.replace("180.00 ", "180.00* ").replace("143.98*", "143.98")
        )
        run.assert_not_called()

    def test_missing_preferred_uses_largest_resolution(self) -> None:
        """Missing preferred uses largest resolution."""
        query = QUERY.replace("59.95 +", "59.95")
        modes = handler.output_modes(query, "DP-4")
        self.assertEqual(handler.select_mode(modes, []).name, "2560x1440")
        self.assertEqual(str(handler.select_mode(modes, []).rate), "180.00")

    def test_explicit_pin_is_honored(self) -> None:
        """Explicit pin is honored."""
        _, run = self.run_handler(pin=("2560x1440", "120"))
        run.assert_called_once_with(
            ["xrandr", "--output", "DP-4", "--mode", "2560x1440", "--rate", "120"], check=False
        )

    def test_unavailable_pin_is_attempted(self) -> None:
        """Unavailable pin is attempted."""
        _, run = self.run_handler(pin=("2560x1440", "300"))
        run.assert_called_once_with(
            ["xrandr", "--output", "DP-4", "--mode", "2560x1440", "--rate", "300"], check=False
        )

    def test_current_rounded_pin_is_unchanged(self) -> None:
        """Current rounded pin is unchanged."""
        _, run = self.run_handler(pin=("2560x1440", "144"))
        run.assert_not_called()

    def test_failed_mode_request_logs_and_falls_back(self) -> None:
        """Failed mode request logs and falls back."""
        with patch.object(sys, "stderr") as stderr:
            _, run = self.run_handler(results=(1, 0))
        self.assertEqual(run.call_args_list[-1].args[0], ["xrandr", "--output", "DP-4", "--auto"])
        self.assertTrue(
            any("mode request failed" in str(call) for call in stderr.write.call_args_list)
        )

    def test_empty_mode_list_falls_back(self) -> None:
        """Empty mode list falls back."""
        _, run = self.run_handler(
            query="DP-4 connected (normal left inverted right x axis y axis)\n"
        )
        run.assert_called_once_with(["xrandr", "--output", "DP-4", "--auto"], check=True)

    def test_disconnect_is_ignored(self) -> None:
        """Disconnect is ignored."""
        read, run = self.run_handler(event="disconnected")
        read.assert_not_called()
        run.assert_not_called()

    def test_query_failure_surfaces(self) -> None:
        """Query failure surfaces."""
        with (
            patch.dict(os.environ, {"SRANDRD_EVENT": "connected", "SRANDRD_OUTPUT": "DP-4"}),
            patch.object(
                handler.subprocess,
                "check_output",
                side_effect=subprocess.CalledProcessError(1, "xrandr"),
            ),
            self.assertRaises(subprocess.CalledProcessError),
        ):
            handler.main()

    def test_fallback_failure_surfaces(self) -> None:
        """Fallback failure surfaces."""
        with (
            patch.dict(os.environ, {"SRANDRD_EVENT": "connected", "SRANDRD_OUTPUT": "DP-4"}),
            patch.object(sys, "argv", [str(HELPER)]),
            patch.object(handler.subprocess, "check_output", return_value=""),
            patch.object(
                handler.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "xrandr")
            ),
            self.assertRaises(subprocess.CalledProcessError),
        ):
            handler.main()


if __name__ == "__main__":
    unittest.main()
