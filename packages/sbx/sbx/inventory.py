# Copyright (c) 2026 Bad3r
"""Listing and describing sandboxes."""

import dataclasses

from sbx import waitqueue
from sbx.context import Context
from sbx.results import Document, Result, SandboxView


class Inventory(Context):
    """`sbx list` and `sbx info`."""

    def listing(self, *, mine: bool) -> list[Result]:
        """Describe every sandbox, or the caller's, then the creates queued for capacity."""
        self._require_session(mine=mine)
        queued: list[Result] = [
            Document(ticket.as_json(position))
            for position, ticket in enumerate(waitqueue.live(self.paths.queue), 1)
            if not mine or ticket.session == self.session
        ]
        if not self.has_state():
            return queued
        sandboxes: list[Result] = [
            self.describe(sandbox)
            for sandbox in self.owned()
            if not mine or sandbox.meta.session == self.session
        ]
        return sandboxes + queued

    def info(self, name: str) -> SandboxView:
        """Describe one sandbox with its files."""
        sandbox = self.find(name)
        return dataclasses.replace(
            self.describe(sandbox),
            console=str(self.paths.sandbox(name) / "console.log"),
            image=sandbox.meta.image,
        )
