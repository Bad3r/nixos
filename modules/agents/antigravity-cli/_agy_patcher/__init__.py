# Copyright (c) 2026 Bad3r

"""Modular ELF/Go structural discovery and binary patching for the `agy` CLI."""

from _agy_patcher.cli import main
from _agy_patcher.discover import (
    DynamicTargets,
    HookSite,
    NoAutoUpdateTargets,
    NoTelemetryTargets,
    QuietWatcherTargets,
    discover_targets,
)
from _agy_patcher.elf import DiscoveryError, Elf64Image, PatchError
from _agy_patcher.go_meta import FuncRange, GoMetadata, find_struct_field_offset
from _agy_patcher.patches import PATCH_SETS, Edit, plan_edits

__all__ = [
    "PATCH_SETS",
    "DiscoveryError",
    "DynamicTargets",
    "Edit",
    "Elf64Image",
    "FuncRange",
    "GoMetadata",
    "HookSite",
    "NoAutoUpdateTargets",
    "NoTelemetryTargets",
    "PatchError",
    "QuietWatcherTargets",
    "discover_targets",
    "find_struct_field_offset",
    "main",
    "plan_edits",
]
