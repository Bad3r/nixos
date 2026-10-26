# Copyright (c) 2026 Bad3r
"""Policy, ceilings, and lifecycle of sbx sandboxes.

Nothing here accepts domain XML or host disk paths: the domain comes from one
template, disks from a built base, and every resource value is checked
against the settings the app module renders.
"""

from typing import TYPE_CHECKING

from sbx.config import Paths
from sbx.gui import Gui
from sbx.inventory import Inventory
from sbx.pipeline import Pipeline
from sbx.prepare import Prepare

if TYPE_CHECKING:
    from sbx.config import Settings
    from sbx.model import Backend


class Sandboxes(Pipeline, Prepare, Inventory, Gui):
    """Every sbx verb, over one backend."""


def open_sandboxes(settings: Settings, session: str | None) -> Sandboxes:
    """Return the sandboxes of one caller over the session daemon, which connects on first use."""

    def connect(require_slice: bool) -> Backend:  # noqa: FBT001
        from sbx.backend import LibvirtBackend  # noqa: PLC0415

        return LibvirtBackend(settings, require_slice=require_slice)

    return Sandboxes(settings, Paths.from_environment(), connect, session)


def running_daemon(settings: Settings) -> Backend:
    """Connect to the session daemon only if it already runs, as the host sleep hook must."""
    from sbx.backend import LibvirtBackend  # noqa: PLC0415

    return LibvirtBackend(settings, require_slice=False, start=False)
