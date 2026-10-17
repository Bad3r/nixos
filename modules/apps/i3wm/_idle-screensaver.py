# Copyright (c) 2026 Bad3r
"""Dismiss the unauthenticated screensaver when X11 activity resumes."""

import signal
import subprocess
import sys
import time
from typing import TYPE_CHECKING, Never

if TYPE_CHECKING:
    from types import FrameType


def idle_milliseconds() -> int:
    return int(subprocess.check_output(["xprintidle"], text=True))


def stop(_signum: int, _frame: FrameType | None) -> Never:
    raise SystemExit(0)


def main() -> None:
    duration = float(sys.argv[1])
    command = sys.argv[2:]
    initial_idle = idle_milliseconds()
    started = time.monotonic()

    for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(signum, stop)

    with subprocess.Popen(command) as screensaver:
        try:
            while screensaver.poll() is None:
                elapsed = time.monotonic() - started
                if elapsed >= duration:
                    break
                if idle_milliseconds() < initial_idle + int(elapsed * 1000):
                    break
                time.sleep(0.1)
            if screensaver.returncode not in (None, 0):
                raise subprocess.CalledProcessError(screensaver.returncode, command)
        finally:
            if screensaver.poll() is None:
                screensaver.terminate()
            screensaver.wait()


if __name__ == "__main__":
    main()
