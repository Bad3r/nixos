# Copyright (c) 2026 Bad3r
"""Select the highest refresh rate at a connected output's preferred resolution."""

import os
import re
import subprocess
import sys
from dataclasses import dataclass
from decimal import Decimal


@dataclass(frozen=True)
class Mode:
    name: str
    rate: Decimal
    preferred: bool
    current: bool


def output_modes(query: str, output: str) -> list[Mode]:
    modes = []
    selected = False
    for line in query.splitlines():
        if line and not line[0].isspace():
            fields = line.split()
            selected = fields[:2] == [output, "connected"]
        elif selected:
            fields = line.split()
            if not fields or not re.fullmatch(r"[0-9]+x[0-9]+", fields[0]):
                continue
            for token in fields[1:]:
                match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)([+*]*)", token)
                if match:
                    modes.append(
                        Mode(
                            fields[0],
                            Decimal(match[1]),
                            "+" in match[2],
                            "*" in match[2],
                        )
                    )
                elif token in ("+", "*") and modes:
                    previous = modes[-1]
                    modes[-1] = Mode(
                        previous.name,
                        previous.rate,
                        previous.preferred or "+" in token,
                        previous.current or "*" in token,
                    )
    return modes


def select_mode(modes: list[Mode], pin: list[str]) -> Mode | None:
    if pin:
        candidates = [mode for mode in modes if mode.name == pin[0]]
        nearest = min(candidates, key=lambda mode: abs(mode.rate - Decimal(pin[1])), default=None)
        return (
            nearest
            if nearest is not None and abs(nearest.rate - Decimal(pin[1])) < Decimal("0.5")
            else None
        )
    preferred = next((mode.name for mode in modes if mode.preferred), None)
    if preferred is None and modes:
        preferred = max(
            modes,
            key=lambda mode: int(mode.name.split("x")[0]) * int(mode.name.split("x")[1]),
        ).name
    return max(
        (mode for mode in modes if mode.name == preferred),
        key=lambda mode: mode.rate,
        default=None,
    )


def main() -> None:
    if os.environ.get("SRANDRD_EVENT") != "connected":
        return
    output = os.environ["SRANDRD_OUTPUT"]
    query = subprocess.check_output(["xrandr", "--query"], text=True)
    modes = output_modes(query, output)
    pin = sys.argv[1:]
    target = select_mode(modes, pin)
    if target is not None and target.current:
        return
    if target is not None or pin:
        name, rate = pin or (target.name, str(target.rate))
        print(f"display-hotplug: requesting {output} {name} at {rate} Hz", file=sys.stderr)
        result = subprocess.run(
            ["xrandr", "--output", output, "--mode", name, "--rate", rate], check=False
        )
        if result.returncode == 0:
            return
        print(
            f"display-hotplug: mode request failed (exit {result.returncode}); "
            "falling back to --auto",
            file=sys.stderr,
        )
    else:
        print(
            f"display-hotplug: no advertised modes for {output}; falling back to --auto",
            file=sys.stderr,
        )
    subprocess.run(["xrandr", "--output", output, "--auto"], check=True)


if __name__ == "__main__":
    main()
