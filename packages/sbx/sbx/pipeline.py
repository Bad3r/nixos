# Copyright (c) 2026 Bad3r
"""One-shot runs: create, copy in, exec, copy out, and destroy."""

from dataclasses import dataclass
from typing import TYPE_CHECKING

from sbx import windows
from sbx.lifecycle import Lifecycle
from sbx.transfer import Transfer

if TYPE_CHECKING:
    from collections.abc import Sequence

    from sbx.model import ExecOptions, ExecResult, Request


@dataclass
class RunResult:
    """What a one-shot run did."""

    sandbox: dict[str, object]
    copied_in: list[dict[str, object]]
    execution: ExecResult
    copied_out: list[dict[str, object]]

    def as_json(self, encoding: str = "text") -> dict[str, object]:
        """Return the JSON form; `encoding` applies to the command's output."""
        return {
            "sandbox": self.sandbox,
            "in": self.copied_in,
            "exec": self.execution.as_json(encoding),
            "out": self.copied_out,
        }


class Pipeline(Lifecycle, Transfer):
    """`sbx run`."""

    def run_once(  # noqa: PLR0913
        self,
        request: Request,
        command: Sequence[str],
        options: ExecOptions,
        *,
        inputs: Sequence[str],
        outputs: Sequence[str],
        to: str | None,
        attached: bool,
    ) -> RunResult:
        """Run one command in a new sandbox, which is destroyed even when a step fails.

        With `attached`, a Linux command runs on the caller's terminal and its
        result carries no output.
        """
        created = self.create(request)
        name, token = str(created["name"]), str(created["token"])
        # Every step and the cleanup act only on this creation, never on a later namesake.
        try:
            agent_only = self.agent_only(name, token=token)
            inbox = windows.INBOX if agent_only else "/root/"
            copied_in = [self.copy(path, f"{name}:{inbox}", token=token) for path in inputs]
            if attached and not agent_only:
                execution = self.exec_attached(name, command, options, token=token)
            else:
                execution = self.exec_capture(name, command, options, token=token)
            copied_out = [self.copy(f"{name}:{path}", to, token=token) for path in outputs]
        finally:
            self.destroy_created(token)
        return RunResult(created, copied_in, execution, copied_out)
