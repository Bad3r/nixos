# Copyright (c) 2026 Bad3r
"""Removal of secrets from text bound for stderr."""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Iterable

MASK = "[redacted]"


class Redactor:
    """Replaces every known secret in a text with a mask."""

    def __init__(self, secrets: Iterable[str]) -> None:
        """Remember the non-empty secrets, longest first."""
        self._secrets = sorted({s for s in secrets if s}, key=len, reverse=True)

    def scrub(self, text: str) -> str:
        """Return text with each secret masked."""
        for secret in self._secrets:
            text = text.replace(secret, MASK)
        return text
