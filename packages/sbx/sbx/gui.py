# Copyright (c) 2026 Bad3r
"""Screenshots and keyboard input of sandboxes with a display."""

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
from sbx.results import KeyResult, ScreenshotResult, TypeResult
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
TYPABLE_CONTROLS = "\n\t"


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
    controls = sorted(
        {
            character
            for character in text
            if unicodedata.category(character) in {"Cc", "Cs"} and character not in TYPABLE_CONTROLS
        }
    )
    if controls:
        return (
            f"type takes no control characters but newline and tab, got "
            f"{', '.join(map(repr, controls))}; press keys with `key`"
        )
    return None


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
            checked(result, "xdotool type")
        return TypeResult(name, len(text))
