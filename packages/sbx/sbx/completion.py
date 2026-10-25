# Copyright (c) 2026 Bad3r
"""Parser-driven shell completion using local state, without starting services."""

import argparse
import os
from pathlib import Path
from typing import Protocol, cast

import argcomplete
from argcomplete.completers import (
    BaseCompleter,
    ChoicesCompleter,
    SuppressCompleter,
)
from argcomplete.lexers import split_line

from sbx import keys, shares
from sbx.core import FLAVOURS, Paths, Settings, remote_name


class PathCompleter(BaseCompleter):
    """Complete host paths without invoking a shell or losing their typed prefix."""

    def __init__(self, *, directories_only: bool = False) -> None:
        """Select files and directories, or directories alone."""
        self.directories_only = directories_only

    def __call__(
        self,
        *,
        prefix: str,
        action: argparse.Action,  # noqa: ARG002
        parser: argparse.ArgumentParser,  # noqa: ARG002
        parsed_args: argparse.Namespace,  # noqa: ARG002
    ) -> list[str]:
        """Return host paths for an argcomplete callback."""
        return self.paths(prefix)

    def paths(self, prefix: str) -> list[str]:
        """Preserve relative paths and tildes while leaving quoting to argcomplete."""
        parent, partial = os.path.split(prefix)
        stem = prefix[: len(prefix) - len(partial)]
        try:
            directory = Path(parent or ".").expanduser()
            entries = list(directory.iterdir())
        except FileNotFoundError, NotADirectoryError, PermissionError, RuntimeError:
            return []
        return sorted(
            stem + entry.name + ("/" if entry.is_dir() else "")
            for entry in entries
            if entry.name.startswith(partial)
            and (partial.startswith(".") or not entry.name.startswith("."))
            and (not self.directories_only or entry.is_dir())
        )


class LocalCompleter(BaseCompleter):
    """Complete bases, sandbox names, copy endpoints, and shares from local files."""

    def __init__(self, kind: str, settings_path: Path) -> None:
        """Bind a candidate kind and the CLI's rendered settings."""
        self.kind = kind
        self.settings_path = settings_path

    def __call__(
        self,
        *,
        prefix: str,
        action: argparse.Action,  # noqa: ARG002
        parser: argparse.ArgumentParser,  # noqa: ARG002
        parsed_args: argparse.Namespace,
    ) -> list[str]:
        """Return candidates; argcomplete applies prefix filtering and shell quoting."""
        if self.kind == "keys":
            stem = prefix.rpartition("+")[0]
            return [f"{stem}+{key}" if stem else key for key in keys.KEYS]
        if self.kind == "shares":
            return [shares.SHARED, *shares.declared(shares.POLICY)]
        if self.kind == "names":
            return [path.name for path in Paths.from_environment().sandbox_dirs()]
        if self.kind == "copy":
            return self._copy(prefix, parsed_args)
        return self._bases()

    def _copy(self, prefix: str, parsed_args: argparse.Namespace) -> list[str]:
        if remote_name(prefix) is not None:
            # Guest paths need a guest command to enumerate, so Tab leaves them alone.
            return []
        # A copy has exactly one guest endpoint.
        source: str | None = getattr(parsed_args, "source", None)
        if source is not None and remote_name(source) is not None:
            return PathCompleter().paths(prefix)
        names = [path.name for path in Paths.from_environment().sandbox_dirs()]
        endpoints = [f"{name}:" for name in names]
        return endpoints if source is not None else [*PathCompleter().paths(prefix), *endpoints]

    def _bases(self) -> list[str]:
        try:
            settings = Settings.load(self.settings_path)
        except FileNotFoundError:
            return list(FLAVOURS) if self.kind == "bases" else []
        if self.kind == "cloud":
            return list(settings.cloud_images)
        windows = [] if settings.windows is None else list(settings.windows.bases)
        return [*FLAVOURS, *settings.cloud_images, *windows]


class CompletingAction(Protocol):
    """The callback attribute argcomplete adds to argparse actions."""

    completer: BaseCompleter


def configure(parser: argparse.ArgumentParser, settings_path: Path) -> None:
    """Attach value completers to every command in the existing parser."""
    kinds = {
        "name": "names",
        "base": "bases",
        "image": "cloud",
        "share": "shares",
        "source": "copy",
        "destination": "copy",
        "keys": "keys",
    }
    completers: dict[str, BaseCompleter] = {
        dest: LocalCompleter(kind, settings_path) for dest, kind in kinds.items()
    }
    completers.update(
        flavour=ChoicesCompleter(dict.fromkeys(FLAVOURS, "Nix base")),
        inputs=PathCompleter(),
        to=PathCompleter(directories_only=True),
    )

    def visit(current: argparse.ArgumentParser) -> None:
        for action in current._actions:  # noqa: SLF001
            choices: object = action.choices
            if isinstance(choices, dict):
                for child in cast("dict[str, object]", choices).values():
                    if isinstance(child, argparse.ArgumentParser):
                        visit(child)
            if action.dest in completers and not (action.dest == "name" and action.option_strings):
                cast("CompletingAction", action).completer = completers[action.dest]

    visit(parser)


def autocomplete(parser: argparse.ArgumentParser, settings_path: Path) -> None:
    """Answer shell completion before CLI parsing, configuration loading, or dispatch."""
    if "_ARGCOMPLETE" not in os.environ:
        return
    line = os.environ["COMP_LINE"]
    point = int(os.environ["COMP_POINT"])
    _quote, _prefix, _suffix, words, _break = split_line(line, point)
    if "--" in words:
        # The CLI reserves everything after -- for the guest, including its options.
        parser = argparse.ArgumentParser(add_help=False)
    else:
        configure(parser, settings_path)
    argcomplete.autocomplete(
        parser, always_complete_options=False, default_completer=SuppressCompleter()
    )
