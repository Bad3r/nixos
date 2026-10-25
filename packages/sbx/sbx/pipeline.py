# Copyright (c) 2026 Bad3r
"""One-shot runs: create, copy in, exec, copy out, and destroy."""

from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING, cast

from sbx import journal, windows
from sbx.errors import SbxError, error_code, error_document
from sbx.lifecycle import Lifecycle
from sbx.model import TRANSPORT_EXIT
from sbx.results import CopyResult, Result
from sbx.transfer import Transfer, guest_source

if TYPE_CHECKING:
    from collections.abc import Sequence

    from sbx.model import ExecOptions, ExecResult, Request


PHASES = ("create", "in", "exec", "out", "cleanup")
# What the run's sandbox was created as; its runtime state is gone once the run ends.
SANDBOX_FIELDS = ("name", "base", "net", "memory_mib", "cpus", "session", "token", "created")


def _phases() -> dict[str, str]:
    return dict.fromkeys(PHASES, "skipped")


@dataclass(frozen=True)
class RunPlan:
    """The host side of a run, checked before it boots."""

    inputs: tuple[Path, ...]
    # Each guest path to copy out, with the host path it lands at.
    outputs: tuple[tuple[str, Path], ...]


@dataclass
class RunResult(Result):
    """What each phase of a one-shot run did: ok, failed, or skipped after a failure."""

    sandbox: dict[str, object]
    phases: dict[str, str] = field(default_factory=_phases)
    copied_in: list[CopyResult] = field(default_factory=list[CopyResult])
    execution: ExecResult | None = None
    copied_out: list[CopyResult] = field(default_factory=list[CopyResult])
    destroyed: list[str] = field(default_factory=list[str])
    cleanup_error: SbxError | OSError | None = None
    # The error that stopped the run at `in` or `exec`.
    failure: SbxError | OSError | None = None

    def failed_phase(self) -> str | None:
        """Return the first phase that did not succeed, or None for a complete run."""
        return next((phase for phase in PHASES if self.phases[phase] != "ok"), None)

    def failed_outputs(self) -> list[CopyResult]:
        """Return the copies out that failed, each with its error."""
        return [entry for entry in self.copied_out if entry.failure is not None]

    def exit_status(self) -> int:
        """Return the command's status."""
        return TRANSPORT_EXIT if self.execution is None else self.execution.status()

    def error(self) -> SbxError | None:
        """Return the run-incomplete error of a run with a failed phase."""
        return None if self.failed_phase() is None else self.incomplete()

    def as_json(self) -> dict[str, object]:
        """Return the JSON form."""
        failed = self.failed_phase()
        return {
            "sandbox": self.sandbox,
            "phases": self.phases,
            "in": [entry.as_json() for entry in self.copied_in],
            "exec": None if self.execution is None else self.execution.as_json(),
            "out": [entry.as_json() for entry in self.copied_out],
            "cleanup": {
                "destroyed": self.destroyed,
                "error": None if self.cleanup_error is None else error_document(self.cleanup_error),
            },
            "failure": None
            if self.failure is None
            else {"phase": failed, **error_document(self.failure)},
        }

    def incomplete(self) -> SbxError:
        """Return the error of a run that did not complete, carrying the whole result."""
        phase = self.failed_phase()
        name = self.sandbox["name"]
        if self.failure is not None:
            detail = str(self.failure)
        elif phase == "exec" and self.execution is not None:
            detail = str(self.execution.transport_error)
        elif phase == "out":
            detail = f"{len(self.failed_outputs())} of {len(self.copied_out)} copies out failed"
        else:
            detail = f"its sandbox may remain: {self.cleanup_error}"
        msg = f"the run in '{name}' failed at {phase}: {detail}"
        return SbxError(msg, code="run-incomplete", details={"phase": phase, "run": self.as_json()})


class Pipeline(Lifecycle, Transfer):
    """`sbx run`."""

    def plan_run(
        self, request: Request, inputs: Sequence[str], outputs: Sequence[str], to: str | None
    ) -> RunPlan:
        """Check a run's host paths, base, network, and disk before it boots or queues.

        Each step checks its own part again when it acts.
        """
        if outputs and to is None:
            msg = "--out needs --to"
            raise SbxError(msg, code="usage")
        if to is not None and not outputs:
            msg = "--to needs --out"
            raise SbxError(msg, code="usage")
        on_windows = self.windows_base(request.base) is not None
        sources = tuple(self._source(Path(path)) for path in inputs)
        landing: dict[str, Path] = {}
        for source in sources:
            # NTFS names in C:\sbx\ ignore case.
            key = source.name.casefold() if on_windows else source.name
            if key in landing:
                msg = f"--in {landing[key]} and {source} both copy in as '{source.name}'"
                raise SbxError(msg, code="invalid-argument")
            landing[key] = source
        targets: dict[Path, str] = {}
        for path in outputs:
            leaf = guest_source(path, on_windows=on_windows).name
            target = self._destination(Path(cast("str", to)), leaf)
            if target in targets:
                msg = f"--out {targets[target]} and {path} both land at {target}"
                raise SbxError(msg, code="invalid-argument")
            targets[target] = path
        self.base_image(request.base)
        if request.net == "egress":
            self._check_egress()
        self.check_disk()
        return RunPlan(sources, tuple((path, target) for target, path in targets.items()))

    def run_once(  # noqa: PLR0913
        self,
        request: Request,
        plan: RunPlan,
        command: Sequence[str],
        options: ExecOptions,
        *,
        attached: bool,
        token: str | None = None,
    ) -> RunResult:
        """Run one command in a new sandbox, which is destroyed even when a step fails.

        A failed create raises its own error. Every later failure lands in the
        result, which keeps the command's result and every copy that worked.
        With `attached`, a Linux command runs on the caller's terminal and its
        result carries no output. `token`, when given, marks the sandbox.
        """
        created = self.create(request, token=token)
        name, token = created.name, str(created.token)
        document = created.as_json()
        result = RunResult({key: document[key] for key in SANDBOX_FIELDS})
        result.phases["create"] = "ok"
        # Every step and the cleanup act only on this creation, never on a later namesake.
        try:
            self._steps(result, plan, command, options, attached=attached)
        finally:
            try:
                result.destroyed = self.destroy_created(token)
                result.phases["cleanup"] = "ok"
            except (SbxError, OSError) as error:
                journal.record(
                    f"cannot destroy run sandbox {name}: {error}", code=error_code(error)
                )
                result.cleanup_error = error
                result.phases["cleanup"] = "failed"
        return result

    def _steps(
        self,
        result: RunResult,
        plan: RunPlan,
        command: Sequence[str],
        options: ExecOptions,
        *,
        attached: bool,
    ) -> None:
        name, token = str(result.sandbox["name"]), str(result.sandbox["token"])
        try:
            agent_only = self.agent_only(name, token=token)
            inbox = windows.INBOX if agent_only else "/root/"
            for source in plan.inputs:
                result.copied_in.append(self.copy(str(source), f"{name}:{inbox}", token=token))
        except (SbxError, OSError) as error:
            result.phases["in"], result.failure = "failed", error
            return
        result.phases["in"] = "ok"
        try:
            if attached and not agent_only:
                execution = self.exec_attached(name, command, options, token=token)
            else:
                execution = self.exec_capture(name, command, options, token=token)
        except (SbxError, OSError) as error:
            result.phases["exec"], result.failure = "failed", error
            return
        result.execution = execution
        # The guest stopped answering, so its files may be incomplete.
        if execution.transport_error is not None:
            result.phases["exec"] = "failed"
            return
        result.phases["exec"] = "ok"
        result.phases["out"] = "ok"
        for path, target in plan.outputs:
            try:
                result.copied_out.append(self.copy(f"{name}:{path}", str(target), token=token))
            except (SbxError, OSError) as error:
                result.copied_out.append(CopyResult(f"{name}:{path}", None, error))
                result.phases["out"] = "failed"
