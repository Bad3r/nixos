# Copyright (c) 2026 Bad3r
"""Policy, ceilings, and lifecycle of sbx sandboxes.

Nothing here accepts domain XML or host disk paths: the domain comes from one
template, disks from a built base, and every resource value is checked
against the settings the app module renders.
"""

from sbx.gui import Gui
from sbx.inventory import Inventory
from sbx.pipeline import Pipeline
from sbx.prepare import Prepare


class Sandboxes(Pipeline, Prepare, Inventory, Gui):
    """Every sbx verb, over one backend."""
