# Copyright (c) 2026 Bad3r
"""Screenshots and keyboard input of sandboxes with a display."""

import time
from datetime import UTC, datetime
from typing import TYPE_CHECKING

from sbx import journal, keys
from sbx.context import Context
from sbx.errors import SbxError
from sbx.model import GUI_BASES
from sbx.proc import run

if TYPE_CHECKING:
    from collections.abc import Sequence

    from sbx.model import Sandbox


KEY_HOLD_MS = 10
# At 20 to 40 ms a character, the longest text `type` takes runs under three minutes.
TYPE_LIMIT = 4096


class Gui(Context):
    """Screenshots, key chords, and typed text."""

    def screenshot(self, name: str, *, ocr: bool) -> dict[str, object]:
        """Save the display under the sandbox's xfer directory, optionally with OCR text."""
        sandbox = self._running(name)
        stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%S")
        partial = self.paths.sandbox(name) / "xfer" / f".screenshot-{stamp}"
        mime = self.backend().screenshot(sandbox.domain.name, partial)
        extension = "png" if mime == "image/png" else "ppm"
        path = partial.with_name(f"screenshot-{stamp}.{extension}")
        partial.replace(path)
        journal.record(f"screenshot of {name}", verb="screenshot", sandbox=name)
        result: dict[str, object] = {"path": str(path), "mime": mime}
        if ocr:
            result["text"] = run([self.settings.tools.tesseract, str(path), "stdout"])
        return result

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

    def key(self, name: str, specs: Sequence[str]) -> dict[str, object]:
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
        return {"sandbox": name, "keys": list(specs)}

    def type_text(self, name: str, text: str) -> dict[str, object]:
        """Type text as US-layout key presses."""
        if len(text) > TYPE_LIMIT:
            msg = f"type takes at most {TYPE_LIMIT} characters, got {len(text)}; split the text"
            raise SbxError(msg, code="invalid-argument")
        try:
            chords = keys.text_chords(text)
        except ValueError as error:
            raise SbxError(str(error), code="invalid-argument") from error
        sandbox = self._gui(name)
        # The text may be a secret the guest asks for, so only its length is logged.
        journal.record(
            f"type in {name}: {len(text)} characters",
            verb="type",
            sandbox=name,
            session=self.session,
        )
        self._send(sandbox.domain.name, chords)
        return {"sandbox": name, "characters": len(text)}
