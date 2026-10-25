# Copyright (c) 2026 Bad3r
"""Screenshots and keyboard input of sandboxes with a display."""

import base64
import binascii
import ctypes
import dataclasses
import re
import secrets
import time
import unicodedata
from datetime import UTC, datetime
from pathlib import Path
from typing import TYPE_CHECKING

from sbx import journal, keys
from sbx.errors import SbxError
from sbx.execution import launcher
from sbx.fsutil import publish
from sbx.model import GUI_BASES, ExecOptions
from sbx.proc import run
from sbx.results import (
    FocusResult,
    KeyResult,
    MouseResult,
    ScreenshotResult,
    TypeResult,
    Window,
    WindowsResult,
)
from sbx.transfer import Transfer

if TYPE_CHECKING:
    from collections.abc import Sequence

    from sbx.model import ExecResult, Sandbox


KEY_HOLD_MS = 10
# At 20 to 40 ms a keycode chord, the longest text `type --mode keys` takes runs under
# three minutes.
TYPE_LIMIT = 4096
# xdotool types in the X session; keys sends keycodes from the host, before X runs too.
TYPE_MODES = ("xdotool", "keys")
# The session's user, which the base lets onto the display next to root.
GUI_USER = "sbx"
DISPLAY = ":0"
# xdotool waits 12 ms after each character, more where it remaps a keycode for one.
TYPE_SECONDS = 0.05
GUEST_TIMEOUT = 30
GUEST_OUTPUT = 64 * 1024
CAPS_LOCK = keys.KEYS["capslock"]
CAPS_LED = "cat /sys/class/leds/input*::capslock/brightness"
LED_VALUE = re.compile(rb"[0-9]{1,3}")
SKIPPED = b"I don't know which key produces"
TYPABLE_CONTROLS = "\n\t"
# X coordinates are signed 16-bit.
MAX_COORDINATE = 32767
BUTTONS = {"left": 1, "middle": 2, "right": 3}
MAX_WINDOW_ID = (1 << 32) - 1
MAX_PATTERN = 1024
NAME_LIMIT = 1024
# xdotool compiles window patterns with glibc's regcomp and these flags, as the host can.
REG_EXTENDED = 1
REG_ICASE = 2
# glibc's regex_t takes 64 bytes on x86_64.
REGEX_SIZE = 256
# A guest script exits so when its window is missing, or its point lies off the display.
INVALID_EXIT = 4
MISSING_EXIT = 3
READY = b"ready\n"
# Shell functions of the window verbs. describe prints one line per window that still
# exists: its id, `getwindowgeometry --shell` on one line, and its name in base64.
WINDOW_HELPERS = """\
describe() {
  for id; do
    geometry=$(xdotool getwindowgeometry --shell "$id" 2>&1) || continue
    case $geometry in *failed*) continue ;; esac
    name=$(xdotool getwindowname "$id" 2>/dev/null | base64 -w0) || continue
    printf '%s %s %s\\n' "$id" "$(printf '%s' "$geometry" | tr '\\n' ' ')" "$name"
  done
}
"""
# Arguments: name or class, pattern. X answers first, so a timeout tells the two waits apart.
WINDOW_WAIT = f"""\
{WINDOW_HELPERS}
until xdotool getdisplaygeometry >/dev/null 2>&1; do sleep 0.2; done
echo ready
ids=$(xdotool search --sync --onlyvisible "--$1" -- "$2") || exit
describe $ids
"""
# Arguments: id or name, the window id or a name pattern.
WINDOW_FOCUS = f"""\
{WINDOW_HELPERS}
target=$2
if [ "$1" = name ]; then
  target=$(xdotool search --onlyvisible --limit 1 --name -- "$2")
fi
[ -n "$target" ] && xdotool getwindowname "$target" >/dev/null 2>&1 || exit {MISSING_EXIT}
xdotool windowactivate --sync "$target" || exit
describe "$target"
"""
WINDOW_LIST = f"""\
{WINDOW_HELPERS}
xdotool getdisplaygeometry >/dev/null || exit
describe $(xdotool search --onlyvisible --name -- '')
"""
# Arguments: x, y, then the button and click count, empty to only move.
MOUSE = f"""\
geometry=$(xdotool getdisplaygeometry) || exit
set -- "$@" $geometry
if [ "$1" -ge "$5" ] || [ "$2" -ge "$6" ]; then
  echo "sbx: $1,$2 lies off the $5x$6 display" >&2
  exit {INVALID_EXIT}
fi
xdotool mousemove --sync "$1" "$2" || exit
[ -z "$3" ] || xdotool click --repeat "$4" "$3"
"""
WINDOW_LINE = re.compile(
    rb"([0-9]{1,10}) WINDOW=([0-9]{1,10}) X=(-?[0-9]{1,6}) Y=(-?[0-9]{1,6}) "
    rb"WIDTH=([0-9]{1,6}) HEIGHT=([0-9]{1,6}) SCREEN=[0-9]{1,3} ([A-Za-z0-9+/]*={0,2})"
)


def _detail(stderr: bytes) -> str:
    """Return a guest's stderr as one bounded line of printable text."""
    text = stderr.decode(errors="replace").strip()
    text = "".join(c if c.isprintable() else " " for c in text)
    return text[:300] or "no message"


def checked(result: ExecResult, what: str) -> ExecResult:
    """Return the result of a guest helper that exited 0; fail with its own words otherwise."""
    if result.transport_error is not None:
        msg = f"{what} failed: {result.transport_error}"
    elif result.timed_out:
        msg = f"{what} did not finish in time"
    elif result.exit_code != 0:
        msg = f"{what} exited {result.status()}: {_detail(result.stderr)}"
    elif result.truncated:
        msg = f"{what} printed more than {GUEST_OUTPUT} bytes"
    else:
        return result
    raise SbxError(msg, code="guest-command")


def _text_refusal(text: str) -> str | None:
    controls = [
        index
        for index, character in enumerate(text)
        if unicodedata.category(character) in {"Cc", "Cs"} and character not in TYPABLE_CONTROLS
    ]
    if controls:
        return (
            f"type takes no control characters but newline and tab, got "
            f"{keys.positions(controls)}; press keys with `key`"
        )
    return None


def _unreadable(detail: str) -> SbxError:
    msg = f"the guest's xdotool printed {detail}"
    return SbxError(msg, code="agent-reply")


def parse_windows(output: bytes) -> tuple[Window, ...]:
    """Read describe's lines; the guest wrote them, so anything off-format fails."""
    windows: list[Window] = []
    for line in output.splitlines():
        match = WINDOW_LINE.fullmatch(line)
        if match is None or match[1] != match[2]:
            detail = "a window line sbx cannot read"
            raise _unreadable(detail)
        try:
            name = base64.b64decode(match[7], validate=True)
        except binascii.Error as error:
            detail = "a window name that is not base64"
            raise _unreadable(detail) from error
        text = name.decode(errors="replace").removesuffix("\n")[:NAME_LIMIT]
        x, y, width, height = (int(match[index]) for index in range(3, 7))
        windows.append(Window(int(match[1]), text, x, y, width, height))
    return tuple(windows)


def regex_error(pattern: str) -> str | None:
    """Return why glibc's regcomp refuses an extended, case-insensitive pattern, or None."""
    libc = ctypes.CDLL("libc.so.6")
    compiled = ctypes.create_string_buffer(REGEX_SIZE)
    code = int(libc.regcomp(compiled, pattern.encode(), REG_EXTENDED | REG_ICASE))
    if code == 0:
        libc.regfree(compiled)
        return None
    message = ctypes.create_string_buffer(256)
    libc.regerror(code, compiled, message, ctypes.sizeof(message))
    return message.value.decode(errors="replace")


def _pattern(pattern: str) -> str:
    if not pattern or len(pattern) > MAX_PATTERN or "\0" in pattern:
        msg = f"a window pattern has 1 to {MAX_PATTERN} characters and no NUL"
        raise SbxError(msg, code="invalid-argument")
    error = regex_error(pattern)
    if error is not None:
        msg = f"{pattern!r} is no extended regular expression: {error}"
        raise SbxError(msg, code="invalid-argument")
    return pattern


class Gui(Transfer):
    """Screenshots, key chords, and typed text."""

    def screenshot(self, name: str, *, ocr: bool, to: str | None = None) -> ScreenshotResult:
        """Save the display, optionally with OCR text, in the xfer directory or at `to`.

        `to` is a directory under the copy roots or a file there that does not
        exist yet; a screenshot never replaces a file.
        """
        stamp = datetime.fromtimestamp(self._clock(), UTC).strftime("%Y%m%dT%H%M%S.%fZ")
        stem = f"screenshot-{stamp}-{secrets.token_hex(3)}"
        if to is not None:
            # The extension follows the capture's MIME type; any leaf checks the roots.
            self._destination(Path(to), f"{stem}.png")
        sandbox = self._running(name)
        xfer = self.paths.sandbox(name) / "xfer"
        partial = xfer / f".screenshot-{secrets.token_hex(8)}"
        try:
            mime = self.backend().screenshot(sandbox.domain.name, partial)
            leaf = f"{stem}.{'png' if mime == 'image/png' else 'ppm'}"
            path = xfer / leaf if to is None else self._destination(Path(to), leaf)
            publish(partial, path)
        finally:
            partial.unlink(missing_ok=True)
        journal.record(f"screenshot of {name} to {path}", verb="screenshot", sandbox=name)
        text = run([self.settings.tools.tesseract, str(path), "stdout"]) if ocr else None
        return ScreenshotResult(str(path), mime, text)

    def _gui(self, name: str) -> Sandbox:
        sandbox = self._running(name)
        if sandbox.meta.base not in GUI_BASES:
            msg = (
                f"sandbox '{name}' runs base {sandbox.meta.base}, which takes no display input; "
                f"GUI bases: {', '.join(sorted(GUI_BASES))}"
            )
            raise SbxError(msg, code="no-display")
        return sandbox

    def _send(self, domain: str, chords: Sequence[Sequence[int]]) -> None:
        backend = self.backend()
        for codes in chords:
            backend.send_key(domain, codes, KEY_HOLD_MS)
            # QEMU queues each press and release behind a hold delay and drops input past
            # 1024 queued events, so each chord drains before the next.
            time.sleep(2 * len(codes) * KEY_HOLD_MS / 1000)

    def key(self, name: str, specs: Sequence[str]) -> KeyResult:
        """Press each chord, such as `ctrl+alt+t` or `enter`, in turn."""
        if len(specs) > keys.MAX_CHORDS:
            msg = f"key takes at most {keys.MAX_CHORDS} chords, got {len(specs)}; split them"
            raise SbxError(msg, code="invalid-argument")
        try:
            chords = [keys.chord(spec) for spec in specs]
        except ValueError as error:
            raise SbxError(str(error), code="invalid-argument") from error
        sandbox = self._gui(name)
        journal.record(
            f"key in {name}: {' '.join(specs)}", verb="key", sandbox=name, session=self.session
        )
        self._send(sandbox.domain.name, chords)
        return KeyResult(name, tuple(specs))

    def session_command(
        self,
        sandbox: Sandbox,
        command: Sequence[str],
        *,
        timeout: float = GUEST_TIMEOUT,
        stdin: bytes | None = None,
    ) -> ExecResult:
        """Run a command through qemu-ga as the session's user, on its display."""
        agent = self._guest_exec(sandbox.domain.name)
        options = ExecOptions(env=(f"DISPLAY={DISPLAY}",), user=GUI_USER)
        argv = launcher(command, options, session=True)
        return agent.run(
            argv[0],
            argv[1:],
            timeout=timeout,
            limit=GUEST_OUTPUT,
            stdin=stdin,
            stops=agent.group_stops(),
        )

    def _caps_lock(self, sandbox: Sandbox) -> bool:
        """Whether a guest keyboard's Caps Lock LED is lit."""
        agent = self._guest_exec(sandbox.domain.name)
        result = agent.run("/bin/sh", ["-c", CAPS_LED], timeout=GUEST_TIMEOUT, limit=4096)
        values = checked(result, "reading the Caps Lock LED").stdout.split()
        if not values or not all(LED_VALUE.fullmatch(value) for value in values):
            msg = "the Caps Lock LED reads as no brightness value"
            raise SbxError(msg, code="agent-reply")
        return any(int(value) for value in values)

    def type_text(self, name: str, text: str, *, mode: str = "xdotool") -> TypeResult:
        """Type text with xdotool in the X session, or as US-layout keycodes in `keys` mode."""
        if len(text) > TYPE_LIMIT:
            msg = f"type takes at most {TYPE_LIMIT} characters, got {len(text)}; split the text"
            raise SbxError(msg, code="invalid-argument")
        chords = None
        if mode == "keys":
            try:
                chords = keys.text_chords(text)
            except ValueError as error:
                msg = f"{error}; --mode keys sends keycodes, and the default mode types any text"
                raise SbxError(msg, code="invalid-argument") from error
        else:
            refusal = _text_refusal(text)
            if refusal is not None:
                raise SbxError(refusal, code="invalid-argument")
        sandbox = self._gui(name)
        # The text may be a secret the guest asks for, so only its length is logged.
        journal.record(
            f"type in {name}: {len(text)} characters",
            verb="type",
            sandbox=name,
            session=self.session,
        )
        if chords is not None:
            if chords and self._caps_lock(sandbox):
                # Caps Lock would flip the case of every letter, so it is off while the text types.
                chords = [[CAPS_LOCK], *chords, [CAPS_LOCK]]
            self._send(sandbox.domain.name, chords)
        elif text:
            command = ["xdotool", "type", "--clearmodifiers", "--file", "-"]
            result = self.session_command(
                sandbox,
                command,
                timeout=GUEST_TIMEOUT + TYPE_SECONDS * len(text),
                stdin=text.encode(),
            )
            # xdotool skips a character it finds no key for with a warning naming it, and
            # exits 0; the text may be a secret, so only the count of those lines is kept.
            lines = result.stderr.splitlines()
            skipped = sum(SKIPPED in line for line in lines)
            stderr = b"\n".join(line for line in lines if SKIPPED not in line)
            checked(dataclasses.replace(result, stderr=stderr), "xdotool type")
            if skipped:
                msg = f"xdotool type found no key for {skipped} of the characters and skipped them"
                raise SbxError(msg, code="guest-command")
        return TypeResult(name, len(text))

    def _window_script(
        self, sandbox: Sandbox, script: str, args: Sequence[str], timeout: float
    ) -> ExecResult:
        result = self.session_command(
            sandbox, ["/bin/sh", "-c", script, "sbx", *args], timeout=timeout
        )
        if result.exit_code == INVALID_EXIT and not result.timed_out:
            raise SbxError(_detail(result.stderr), code="invalid-argument")
        return result

    def mouse(
        self, name: str, x: int, y: int, *, click: str | None = None, double: bool = False
    ) -> MouseResult:
        """Move the pointer to a display pixel through xdotool, then click there if asked."""
        if not (0 <= x <= MAX_COORDINATE and 0 <= y <= MAX_COORDINATE):
            msg = f"mouse takes coordinates from 0 to {MAX_COORDINATE}, not {x},{y}"
            raise SbxError(msg, code="invalid-argument")
        if click is not None and click not in BUTTONS:
            msg = f"mouse clicks {', '.join(BUTTONS)}, not {click!r}"
            raise SbxError(msg, code="invalid-argument")
        if double and click is None:
            click = "left"
        sandbox = self._gui(name)
        journal.record(
            f"mouse in {name}: {click or 'move'}{' twice' if double else ''} at {x},{y}",
            verb="mouse",
            sandbox=name,
            session=self.session,
        )
        button = "" if click is None else str(BUTTONS[click])
        result = self._window_script(
            sandbox, MOUSE, [str(x), str(y), button, "2" if double else "1"], GUEST_TIMEOUT
        )
        checked(result, "xdotool mousemove")
        return MouseResult(name, x, y, click, double)

    def window_wait(self, name: str, kind: str, pattern: str, timeout: float) -> WindowsResult:
        """Wait until X answers and a visible window's name or class matches the pattern."""
        if kind not in {"name", "class"}:
            msg = f"window wait matches a name or a class, not {kind!r}"
            raise SbxError(msg, code="internal")
        pattern = _pattern(pattern)
        sandbox = self._gui(name)
        result = self._window_script(sandbox, WINDOW_WAIT, [kind, pattern], timeout)
        if result.timed_out:
            if result.stdout.startswith(READY):
                msg = f"no visible window of {name} matched {kind} {pattern!r} in {timeout:g} s"
            else:
                msg = f"the display of {name} did not answer in {timeout:g} s"
            raise SbxError(msg, code="window-timeout")
        output = checked(result, "xdotool search").stdout
        if not output.startswith(READY):
            detail = "no readiness line"
            raise _unreadable(detail)
        return WindowsResult(name, parse_windows(output.removeprefix(READY)))

    def window_focus(
        self, name: str, *, window: int | None = None, pattern: str | None = None
    ) -> FocusResult:
        """Activate a window by id, or the first visible one whose name matches."""
        if window is not None:
            if not 0 < window <= MAX_WINDOW_ID:
                msg = f"a window id lies from 1 to {MAX_WINDOW_ID}, not {window}"
                raise SbxError(msg, code="invalid-argument")
            args = ["id", str(window)]
        elif pattern is not None:
            args = ["name", _pattern(pattern)]
        else:
            msg = "window focus takes an id or a name pattern"
            raise SbxError(msg, code="usage")
        sandbox = self._gui(name)
        journal.record(
            f"window focus in {name}: {args[0]} {args[1]}",
            verb="window",
            sandbox=name,
            session=self.session,
        )
        result = self._window_script(sandbox, WINDOW_FOCUS, args, GUEST_TIMEOUT)
        if result.exit_code == MISSING_EXIT and not result.timed_out:
            msg = f"no window of {name} has {args[0]} {args[1]!r}"
            raise SbxError(msg, code="no-window")
        windows = parse_windows(checked(result, "xdotool windowactivate").stdout)
        if len(windows) != 1:
            msg = f"the focused window of {name} closed before sbx could describe it"
            raise SbxError(msg, code="no-window")
        return FocusResult(name, windows[0])

    def window_list(self, name: str) -> WindowsResult:
        """Describe every visible window."""
        sandbox = self._gui(name)
        result = self._window_script(sandbox, WINDOW_LIST, [], GUEST_TIMEOUT)
        return WindowsResult(name, parse_windows(checked(result, "xdotool search").stdout))
