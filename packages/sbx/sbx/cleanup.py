# Copyright (c) 2026 Bad3r
"""Garbage collection of sandboxes and superseded base exports."""

import shutil
import subprocess
from pathlib import Path
from typing import TYPE_CHECKING

from sbx import cloud, journal, windows
from sbx.storage import Storage

if TYPE_CHECKING:
    from collections.abc import Sequence

    from sbx.model import Sandbox


class Cleanup(Storage):
    """Removal of stopped, expired, and half-removed sandboxes."""

    def host_synced(self) -> bool:
        """Return whether timedatectl reports the host clock NTP-synchronized."""
        show = [self.settings.tools.timedatectl, "show", "-p", "NTPSynchronized", "--value"]
        result = subprocess.run(show, capture_output=True, text=True, check=False)
        return result.stdout.strip() == "yes"

    def _gc_reason(self, sandbox: Sandbox, now: float, *, synced: bool) -> str | None:
        # An unsynced clock, such as the RTC's right after resume, may run hours ahead.
        if synced and sandbox.meta.expires <= now:
            return "expired"
        # A prepare guest powers itself off before its disk is published.
        preparing = sandbox.name.startswith(cloud.PREPARE_PREFIX)
        if not sandbox.domain.active and not sandbox.domain.managed_save and not preparing:
            return "shut off"
        if not self.paths.sandbox(sandbox.name).is_dir():
            return "run directory missing"
        return None

    def gc(self, *, dry_run: bool) -> list[dict[str, str]]:
        """Remove stopped, half-removed, and, on a synced clock, expired sandboxes; then exports."""
        has_state = self.has_state()
        if not has_state and self.settings.windows is None:
            return []
        with self.locked():
            # Without sandbox state, gc never starts the daemon.
            actions, kept = self._gc_sandboxes(dry_run=dry_run) if has_state else ([], [])
            pruned = self._prune_bases(kept, dry_run=dry_run)
        if not dry_run:
            for action in actions:
                journal.record(
                    f"gc removed sandbox {action['name']}: {action['reason']}",
                    verb="gc",
                    sandbox=action["name"],
                )
            for action in pruned:
                journal.record(f"gc removed base export {action['name']}", verb="gc")
        return actions + pruned

    def _gc_sandboxes(self, *, dry_run: bool) -> tuple[list[dict[str, str]], list[Sandbox]]:
        """Remove what gc removes under the held lock; return the actions and the survivors."""
        actions: list[dict[str, str]] = []
        kept: list[Sandbox] = []
        synced = self.host_synced()
        now = self._clock()
        owned = {sandbox.name: sandbox for sandbox in self.owned()}
        for sandbox in owned.values():
            reason = self._gc_reason(sandbox, now, synced=synced)
            if reason is None:
                kept.append(sandbox)
                continue
            actions.append({"name": sandbox.name, "reason": reason})
            if not dry_run:
                self._discard(sandbox.name)
        for directory in self.paths.sandbox_dirs():
            if directory.name in owned:
                continue
            actions.append({"name": directory.name, "reason": "no domain"})
            if not dry_run:
                self._discard(directory.name)
        return actions, kept

    def _prune_bases(self, kept: Sequence[Sandbox], *, dry_run: bool) -> list[dict[str, str]]:
        """Remove Windows base exports that are neither the newest nor under a sandbox."""
        settings = self.settings.windows
        if settings is None:
            return []
        used = {Path(sandbox.meta.image).parent for sandbox in kept}
        actions: list[dict[str, str]] = []
        for base, directory in settings.bases.items():
            for version in windows.versions(directory)[:-1]:
                if version in used:
                    continue
                actions.append({"name": f"{base}/{version.name}", "reason": "superseded export"})
                if not dry_run:
                    shutil.rmtree(version)
        return actions
