# Copyright (c) 2026 Bad3r
"""Select the highest refresh rate at a connected output's preferred resolution.

On NVIDIA, the mode is set through a MetaMode that keeps AllowGSYNCCompatible.
"""

import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal


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


def split_metamode(metamode: str) -> list[str]:
    entries = []
    depth = 0
    start = 0
    for index, char in enumerate(metamode):
        depth += {"{": 1, "}": -1}.get(char, 0)
        if char == "," and depth == 0:
            entries.append(metamode[start:index].strip())
            start = index + 1
    entries.append(metamode[start:].strip())
    # A MetaMode with no enabled display reads as a bare NULL.
    return [entry for entry in entries if entry and entry != "NULL"]


def with_gsync_compatible(entry: str) -> str:
    if "AllowGSYNCCompatible=" in entry:
        return entry
    if entry.endswith("}"):
        return f"{entry[:-1]}, AllowGSYNCCompatible=On}}"
    return f"{entry} {{AllowGSYNCCompatible=On}}"


def nvidia_mode_name(name: str, rate: str) -> str:
    # The driver names modes <width>x<height>_<refresh rounded to an integer>.
    return f"{name}_{Decimal(rate).to_integral_value(rounding=ROUND_HALF_UP)}"


def run_nvidia_settings(nvidia_settings: str, *args: str) -> str:
    result = subprocess.run([nvidia_settings, *args], capture_output=True, text=True, check=True)
    # nvidia-settings exits 0 after rejecting a query or assignment.
    if "ERROR:" in result.stdout + result.stderr:
        msg = f"nvidia-settings {' '.join(args)}: {(result.stdout + result.stderr).strip()}"
        raise RuntimeError(msg)
    return result.stdout


def set_metamode(nvidia_settings: str, output: str, mode: str | None) -> None:
    current = run_nvidia_settings(nvidia_settings, "-t", "-q", "CurrentMetaMode").strip()
    _, separator, metamode = current.partition(" :: ")
    if not separator:
        msg = f"unexpected CurrentMetaMode output: {current!r}"
        raise RuntimeError(msg)
    device = re.search(
        rf"\[dpy:([0-9]+)\] \({re.escape(output)}\)",
        run_nvidia_settings(nvidia_settings, "-q", "dpys"),
    )
    if device is None:
        msg = f"no NVIDIA display device named {output}"
        raise RuntimeError(msg)
    entries = split_metamode(metamode)
    own = next(
        (index for index, entry in enumerate(entries) if entry.startswith(f"DPY-{device[1]}:")),
        None,
    )
    fields = entries[own].split(":", 1)[1].split("{", 1)[0].split() if own is not None else []
    current_mode = fields[0] if fields and fields[0] != "NULL" else None
    wanted = mode or current_mode or "nvidia-auto-select"
    updated = [with_gsync_compatible(entry) for entry in entries]
    if current_mode != wanted:
        position = next(
            (field for field in fields if re.fullmatch(r"[+-][0-9]+[+-][0-9]+", field)), "+0+0"
        )
        entry = f"DPY-{device[1]}: {wanted} {position} {{AllowGSYNCCompatible=On}}"
        if own is None:
            updated.append(entry)
        else:
            updated[own] = entry
    if updated == entries:
        return
    print(f"display-hotplug: assigning MetaMode {', '.join(updated)}", file=sys.stderr)
    run_nvidia_settings(nvidia_settings, "--assign", f"CurrentMetaMode={', '.join(updated)}")


def set_primary(output: str, primary: list[str]) -> None:
    if primary:
        print(f"display-hotplug: setting {output} as primary", file=sys.stderr)
        subprocess.run(["xrandr", "--output", output, *primary], check=True)


def set_mode(output: str, pin: list[str], nvidia_settings: str | None) -> None:
    query = subprocess.check_output(["xrandr", "--query"], text=True)
    modes = output_modes(query, output)
    target = select_mode(modes, pin)
    # Without a primary output, i3bar's tray_output primary shows no tray.
    primary = [] if re.search(r"^\S+ connected primary ", query, re.MULTILINE) else ["--primary"]
    if nvidia_settings:
        # RandR-created MetaModes drop AllowGSYNCCompatible, so one MetaMode
        # assignment sets the mode and the attribute together.
        mode = nvidia_mode_name(*pin) if pin else None
        if mode is None and target is not None:
            mode = nvidia_mode_name(target.name, str(target.rate))
        try:
            set_metamode(nvidia_settings, output, mode)
        except (RuntimeError, subprocess.CalledProcessError) as error:
            print(f"display-hotplug: {error}; falling back to xrandr", file=sys.stderr)
        else:
            set_primary(output, primary)
            return
    if target is not None and target.current:
        set_primary(output, primary)
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
    set_mode(os.environ["SRANDRD_OUTPUT"], args.pin, args.nvidia_settings)


if __name__ == "__main__":
    main()
