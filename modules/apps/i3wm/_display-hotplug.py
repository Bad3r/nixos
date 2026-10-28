# Copyright (c) 2026 Bad3r
"""Select the highest refresh rate at a connected output's preferred resolution."""

import argparse
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


def with_gsync_compatible(metamode: str) -> str:
    entries = []
    depth = 0
    start = 0
    for index, char in enumerate(metamode):
        depth += {"{": 1, "}": -1}.get(char, 0)
        if char == "," and depth == 0:
            entries.append(metamode[start:index].strip())
            start = index + 1
    entries.append(metamode[start:].strip())
    updated = []
    for entry in entries:
        if "AllowGSYNCCompatible=" in entry:
            updated.append(entry)
        elif entry.endswith("}"):
            updated.append(f"{entry[:-1]}, AllowGSYNCCompatible=On}}")
        else:
            updated.append(f"{entry} {{AllowGSYNCCompatible=On}}")
    return ", ".join(updated)


def allow_gsync_compatible(nvidia_settings: str) -> None:
    current = subprocess.check_output(
        [nvidia_settings, "-t", "-q", "CurrentMetaMode"], text=True
    ).strip()
    _, separator, metamode = current.partition(" :: ")
    if not separator:
        msg = f"unexpected CurrentMetaMode output: {current!r}"
        raise RuntimeError(msg)
    updated = with_gsync_compatible(metamode)
    if updated == metamode:
        return
    print(f"display-hotplug: assigning MetaMode {updated}", file=sys.stderr)
    subprocess.run([nvidia_settings, "--assign", f"CurrentMetaMode={updated}"], check=True)


def set_mode(output: str, pin: list[str]) -> None:
    query = subprocess.check_output(["xrandr", "--query"], text=True)
    modes = output_modes(query, output)
    target = select_mode(modes, pin)
    # Without a primary output, i3bar's tray_output primary shows no tray.
    primary = [] if re.search(r"^\S+ connected primary ", query, re.MULTILINE) else ["--primary"]
    if target is not None and target.current:
        if primary:
            print(f"display-hotplug: setting {output} as primary", file=sys.stderr)
            subprocess.run(["xrandr", "--output", output, *primary], check=True)
        return
    if target is not None or pin:
        name, rate = pin or (target.name, str(target.rate))
        print(f"display-hotplug: requesting {output} {name} at {rate} Hz", file=sys.stderr)
        result = subprocess.run(
            ["xrandr", "--output", output, "--mode", name, "--rate", rate, *primary],
            check=False,
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
    subprocess.run(["xrandr", "--output", output, "--auto", *primary], check=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--nvidia-settings")
    parser.add_argument("pin", nargs="*")
    args = parser.parse_args()
    if os.environ.get("SRANDRD_EVENT") != "connected":
        return
    set_mode(os.environ["SRANDRD_OUTPUT"], args.pin)
    # RandR-created MetaModes drop per-mode attributes.
    if args.nvidia_settings:
        allow_gsync_compatible(args.nvidia_settings)


if __name__ == "__main__":
    main()
