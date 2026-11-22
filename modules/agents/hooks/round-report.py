# Copyright (c) 2026 Bad3r

"""Round report hooks for Claude Code and Codex.

Subcommands, each reading its hook payload on stdin:
  log-failure  PostToolUseFailure: append the failed call to the session log.
  round-start  UserPromptSubmit: snapshot the git working tree.
  round-end    Stop: show the files changed and calls failed this round, and
               send the agent back once to account for them.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import IO, cast

type Json = dict[str, object]

SCRATCH = Path(os.environ["ROUND_REPORT_SCRATCH"])
LIST_CAP = 20
# Larger files or large snapshots fingerprint by size and mtime instead of reading contents.
HASH_MAX_BYTES = 1 << 20
HASH_COUNT_CAP = 200
# Untracked directories past this count collapse to one tree entry, and total
# untracked entries are capped so an untracked checkout cannot stall hooks.
UNTRACKED_DIR_CAP = 200
UNTRACKED_CAP = 500
PORCELAIN_PREFIX = 3
# Exit 1 from these as the last command means "no match" or "differs".
NO_MATCH = re.compile(
    r"(?:^|[|;&]\s*)(?:grep|rg|egrep|fgrep|diff|test|\[|git\s+(?:diff|grep))(?:\s|$)[^|;&]*$",
)
REDIRECT = re.compile(r"(?<!\d)\d{0,4}>&\d+|&>")
INPUT_KEYS = ("command", "cmd", "file_path", "path", "url", "pattern", "code")


def state_dir(payload: Json) -> Path:
    """Return the per-session state directory, creating it."""
    session = str(payload.get("session_id") or "unknown")
    if session in {".", ".."} or any(sep in session for sep in ("/", "\\", "\0")):
        message = f"invalid session id {session!r}"
        raise ValueError(message)
    root = os.path.normpath(SCRATCH / "sessions")
    target = os.path.normpath(f"{root}/{session}/hooks/round-report")
    if not target.startswith(root + os.sep):
        message = f"session id {session!r} leaves {root}"
        raise ValueError(message)
    path = Path(target)
    path.mkdir(parents=True, exist_ok=True)
    return path


GIT_TIMEOUT_S = 15


def git(cwd: Path, *args: str) -> str | None:
    """Run git in cwd without optional locks; None when it fails or times out."""
    try:
        result = subprocess.run(
            ["git", "--no-optional-locks", "-C", str(cwd), *args],
            capture_output=True,
            text=True,
            timeout=GIT_TIMEOUT_S,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return None
    return result.stdout if result.returncode == 0 else None


def porcelain_entries(status: str) -> tuple[dict[str, str], list[str]]:
    """Split NUL-separated porcelain v1 paths into tracked code map and untracked list."""
    tracked: dict[str, str] = {}
    untracked: list[str] = []
    entries = iter(status.split("\0"))
    for entry in entries:
        if len(entry) <= PORCELAIN_PREFIX:
            continue
        code, path = entry[:2], entry[PORCELAIN_PREFIX:]
        if code == "??":
            untracked.append(path)
            continue
        tracked[path] = code
        if "R" in code or "C" in code:
            source = next(entries, "")
            if source:
                tracked.setdefault(source, code)
    return tracked, untracked


def untracked_members(top: Path, entry: str) -> list[str] | None:
    """Untracked, non-ignored files under a directory; None past UNTRACKED_DIR_CAP."""
    command = [
        "git",
        "--no-optional-locks",
        "--literal-pathspecs",
        "-C",
        str(top),
        "ls-files",
        "-z",
        "--others",
        "--exclude-standard",
        "--",
        entry,
    ]
    members: list[str] = []
    pending = b""
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL) as proc:
        stdout = cast("IO[bytes]", proc.stdout)
        while chunk := stdout.read(1 << 16):
            *names, pending = (pending + chunk).split(b"\0")
            members += [name.decode(errors="surrogateescape") for name in names if name]
            if len(members) > UNTRACKED_DIR_CAP:
                proc.kill()
                return None
    if proc.returncode != 0:
        return [entry]
    return members


def expand_untracked(top: Path, entries: list[str]) -> tuple[list[str], dict[str, str], str | None]:
    """Expand small untracked directories to file paths; collapse huge ones early."""
    kept: list[str] = []
    collapsed: dict[str, str] = {}
    truncated = False
    for entry in entries:
        if len(kept) >= UNTRACKED_CAP:
            truncated = True
            break
        if not entry.endswith("/") or (top / entry / ".git").exists():
            kept.append(entry)
            continue
        members = untracked_members(top, entry)
        if members is None:
            collapsed[entry] = f"tree:>{UNTRACKED_DIR_CAP}"
        else:
            kept.extend(members)
    if len(kept) > UNTRACKED_CAP:
        truncated = True
        kept = kept[:UNTRACKED_CAP]
    cutoff = kept[-1] if truncated and kept else None
    return kept, collapsed, cutoff


def past_cutoff(path: str, cutoff: str | None) -> bool:
    """Tell whether path sorts past the start snapshot's truncated untracked window."""
    if cutoff is None:
        return False
    return path.encode("utf-8", "surrogateescape") > cutoff.encode("utf-8", "surrogateescape")


def path_state(path: Path, *, hash_content: bool = True) -> str:
    """Fingerprint one dirty path: content hash, size and mtime, link target, or nested repo."""
    try:
        if path.is_symlink():
            return "link:" + str(path.readlink())
        if path.is_dir():
            nested = git(path, "status", "--porcelain=v1", "-z") or ""
            head = git(path, "rev-parse", "HEAD") or ""
            return "dir:" + hashlib.sha256((head + nested).encode()).hexdigest()
        if path.is_file():
            info = path.stat()
            if not hash_content or info.st_size > HASH_MAX_BYTES:
                return f"stat:{info.st_size}:{info.st_mtime_ns}"
            return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError as error:
        return f"unreadable:{error.errno}"
    return "absent"


def snapshot(
    cwd: Path,
    *,
    hash_content: bool | None = None,
    known: set[str] | None = None,
    known_trees: set[str] | None = None,
    untracked_end: str | None = None,
) -> Json | None:
    """Record HEAD and a fingerprint of every dirty or known path in cwd's repository."""
    top_out = git(cwd, "rev-parse", "--show-toplevel")
    if top_out is None:
        return None
    top = Path(top_out.removesuffix("\n"))
    head = (git(top, "rev-parse", "--verify", "-q", "HEAD") or "").removesuffix("\n")
    status = git(top, "status", "--porcelain=v1", "-z", "--untracked-files=normal")
    if status is None:
        return None
    tracked, untracked = porcelain_entries(status)
    kept_untracked, collapsed, cutoff = expand_untracked(top, untracked)
    paths = list(tracked) + kept_untracked
    use_hash = len(paths) <= HASH_COUNT_CAP if hash_content is None else hash_content
    files: dict[str, str] = {}
    for p in paths:
        if (
            p not in tracked
            and known is not None
            and p not in known
            and past_cutoff(p, untracked_end)
        ):
            continue
        prefix = f"{tracked[p]}:" if p in tracked else ""
        # At round end, paths absent from the start snapshot are already known changed.
        if known is not None and p not in known:
            files[p] = f"{prefix}new"
        else:
            files[p] = f"{prefix}{path_state(top / p, hash_content=use_hash)}"
    for entry, tree_state in collapsed.items():
        if (
            known_trees is not None
            and entry not in known_trees
            and past_cutoff(entry, untracked_end)
        ):
            continue
        files[entry] = tree_state
    # Paths dirty at round start get a state even when clean or past the
    # untracked cap now, so a cap window that shifts reports nothing.
    for p in known or ():
        if p not in files:
            files[p] = path_state(top / p, hash_content=use_hash)
    return {
        "top": str(top),
        "head": head,
        "hashed": use_hash,
        "untracked_end": cutoff,
        "files": files,
    }


def changed_files(start: Json | None, end: Json | None) -> list[str]:
    """Paths whose working-tree state or committed content changed between snapshots."""
    if start is None or end is None or start["top"] != end["top"]:
        return []
    start_files = cast("dict[str, str]", start["files"])
    end_files = cast("dict[str, str]", end["files"])
    names = set(start_files) | set(end_files)
    collapsed_roots = [
        n
        for n in names
        if start_files.get(n, "").startswith("tree:") or end_files.get(n, "").startswith("tree:")
    ]
    changed: set[str] = set()
    for name in names:
        if start_files.get(name) == end_files.get(name):
            continue
        parent = next(
            (root for root in collapsed_roots if name != root and name.startswith(root)),
            None,
        )
        changed.add(parent or name)
    start_head, end_head = str(start["head"]), str(end["head"])
    top = Path(str(end["top"]))
    if end_head and start_head != end_head:
        committed = (
            git(top, "diff", "--name-only", "-z", "--no-renames", start_head, end_head)
            if start_head
            else git(top, "ls-tree", "-r", "--name-only", "-z", end_head)
        )
        changed.update(p for p in (committed or "").split("\0") if p)
    return sorted(changed)


def in_codex_home(cwd: Path) -> bool:
    """Codex's own background threads (memory consolidation) run inside CODEX_HOME."""
    home = os.environ.get("CODEX_HOME")
    if not home:
        return False
    home_path = Path(home)
    if not home_path.is_absolute():
        home_path = Path.cwd() / home_path
    codex_root = Path(os.path.normpath(home_path))
    cwd_norm = Path(os.path.normpath(cwd if cwd.is_absolute() else Path.cwd() / cwd))
    return cwd_norm.is_relative_to(codex_root) or cwd.resolve().is_relative_to(codex_root)


def round_key(payload: Json) -> str:
    """Codex scopes a round to its turn id; Claude has one round at a time."""
    return str(payload.get("turn_id") or "main")


def read_state(path: Path) -> Json:
    """Load the state file, or an empty state."""
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except OSError, ValueError:
        return {}
    return cast("Json", value) if isinstance(value, dict) else {}


def write_state(path: Path, value: Json) -> None:
    """Replace the state file atomically."""
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(value), encoding="utf-8")
    tmp.replace(path)


def first_line(text: object, limit: int = 200) -> str:
    """First non-blank line of text, shortened."""
    for line in str(text or "").splitlines():
        if line.strip():
            return line.strip()[:limit]
    return ""


def span(text: object, limit: int = 160) -> str:
    """First and last non-blank lines of text; the last one decides a script's exit."""
    lines = [line.strip() for line in str(text).splitlines() if line.strip()]
    if len(lines) > 1:
        return f"{lines[0][: limit // 2]} ... {lines[-1][: limit // 2]}"
    return lines[0][:limit] if lines else ""


def describe_input(tool_input: object) -> str:
    """A one-line description of a tool call's input."""
    if isinstance(tool_input, dict):
        fields = cast("Json", tool_input)
        for key in INPUT_KEYS:
            if fields.get(key):
                return span(fields[key])
    return first_line(json.dumps(tool_input), 160)


def tool_command(tool_input: object) -> str:
    """The shell command of a Bash call, or an empty string."""
    if isinstance(tool_input, dict):
        return str(cast("Json", tool_input).get("command") or "")
    return ""


def log_failure(payload: Json) -> Json | None:
    """Append one failed tool call to the session log."""
    agent = str(payload.get("agent_type") or "main")
    if payload.get("is_interrupt") or agent.endswith("-observer"):
        return None
    error = str(payload.get("error") or "")
    tool_input: object = payload.get("tool_input")
    command = tool_command(tool_input)
    last_command = REDIRECT.sub("", (command.strip().splitlines() or [""])[-1])
    exit_match = re.match(r"Exit code (\d+)", error)
    detail = error.split("\n", 1)[-1] if exit_match else error
    entry = {
        "time": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "agent": agent,
        "tool": payload.get("tool_name"),
        "input": describe_input(tool_input),
        "error": first_line(detail) or first_line(error),
        "exit": int(exit_match.group(1)) if exit_match else None,
        "benign": bool(
            payload.get("tool_name") == "Bash"
            and exit_match
            and exit_match.group(1) == "1"
            and NO_MATCH.search(last_command.strip()),
        ),
    }
    with (state_dir(payload) / "failures.jsonl").open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry) + "\n")
    return None


def log_line_count(log_path: Path) -> int:
    """Number of recorded lines in the failure log, or 0 if absent."""
    try:
        return len(log_path.read_text(encoding="utf-8").splitlines())
    except OSError:
        return 0


def round_start(payload: Json) -> Json | None:
    """Snapshot the working tree and failure-log cursor at the start of a main-agent round."""
    cwd = Path(str(payload.get("cwd") or Path.cwd()))
    if payload.get("agent_id") or in_codex_home(cwd):
        return None
    directory = state_dir(payload)
    state_path = directory / "state.json"
    state = read_state(state_path)
    state["cursor"] = log_line_count(directory / "failures.jsonl")
    state["starts"] = {round_key(payload): snapshot(cwd)}
    write_state(state_path, state)
    return None


def capped(items: list[str]) -> list[str]:
    """At most LIST_CAP items, with a count of the rest."""
    more = len(items) - LIST_CAP
    return items[:LIST_CAP] + ([f"... and {more} more"] if more > 0 else [])


def new_failures(log_path: Path, cursor: int) -> tuple[list[Json], int]:
    """Non-benign log entries past cursor, and the new cursor."""
    try:
        lines = log_path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return [], cursor
    failures: list[Json] = []
    for line in lines[cursor:]:
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if isinstance(entry, dict) and not cast("Json", entry).get("benign"):
            failures.append(cast("Json", entry))
    return failures, len(lines)


def block_reason(unmentioned: list[str], failure_lines: list[str]) -> str:
    """The instruction that sends the agent back to complete its summary."""
    reason = ["Round report check: before ending, revise your summary so that it:"]
    if unmentioned:
        reason.append(
            "- names each of these files that git shows changed this round, and says so "
            "where another session sharing the tree changed one:",
        )
        reason += [f"    {f}" for f in capped(unmentioned)]
    if failure_lines:
        reason.append(
            "- accounts for each failed tool call below: what failed, why, and whether it "
            "affects the result; call one unrelated only with the evidence:",
        )
        reason += [f"    {f}" for f in capped(failure_lines)]
    reason.append(
        "- quotes the result lines of every test or check you ran, failures and skips included.",
    )
    return "\n".join(reason)


def round_end(payload: Json) -> Json | None:
    """Report the round's changed files and failures; block once if unaccounted."""
    if in_codex_home(Path(str(payload.get("cwd") or Path.cwd()))):
        return None
    directory = state_dir(payload)
    state_path = directory / "state.json"
    log_path = directory / "failures.jsonl"
    state = read_state(state_path)
    failures, cursor = new_failures(log_path, int(cast("int", state.get("cursor", 0))))
    starts = cast("dict[str, Json | None]", state.get("starts") or {})
    start = starts.get(round_key(payload))
    start_files = cast("dict[str, str]", start["files"]) if start else {}
    end = (
        snapshot(
            Path(str(start["top"])),
            hash_content=bool(start.get("hashed", True)),
            known={
                name
                for name, entry_state in start_files.items()
                if not entry_state.startswith("tree:")
            },
            known_trees={
                name for name, entry_state in start_files.items() if entry_state.startswith("tree:")
            },
            untracked_end=cast("str | None", start.get("untracked_end")),
        )
        if start
        else None
    )
    output = round_output(
        payload,
        changed_files(start, end),
        failures,
        log_path,
        top=str(start["top"]) if start else None,
    )
    state["cursor"] = cursor
    if output is None or "decision" not in output:
        starts.pop(round_key(payload), None)
    state["starts"] = starts
    write_state(state_path, state)
    return output


def path_mentioned(path: str, message: str, top: str | None = None) -> bool:
    """Tell whether path appears as a complete relative or repo-rooted path token."""
    prefixes = [r"\./"]
    if top:
        clean_top = top.rstrip("/")
        prefixes.append(rf"(?:file://)?{re.escape(clean_top)}/")
        home = os.environ.get("HOME", "").rstrip("/")
        if home and clean_top == home:
            prefixes.append(r"~/")
        elif home and clean_top.startswith(home + "/"):
            prefixes.append(rf"~/{re.escape(clean_top.removeprefix(home + '/'))}/")
    prefix = f"(?:{'|'.join(prefixes)})?"
    target = rf"{re.escape(path.rstrip('/'))}/?" if path.endswith("/") else re.escape(path)
    return bool(
        re.search(
            rf"(?<![A-Za-z0-9_./~-]){prefix}{target}(?![A-Za-z0-9_/-]|\.[A-Za-z0-9_-])",
            message,
        ),
    )


def round_output(
    payload: Json,
    files: list[str],
    failures: list[Json],
    log_path: Path,
    *,
    top: str | None = None,
) -> Json | None:
    """The round report, with a block when files or failures are unaccounted for."""
    if not files and not failures:
        return None

    failure_lines = [
        f"{e.get('agent')} {e.get('tool')}: {e.get('input')} -> {e.get('error') or 'failed'}"
        for e in failures
    ]
    shown: list[str] = []
    if files:
        shown.append(f"Files changed this round ({len(files)}):")
        shown += [f"  {f}" for f in capped(files)]
    if failures:
        shown.append(f"Failed tool calls this round ({len(failures)}), log {log_path}:")
        shown += [f"  {f}" for f in capped(failure_lines)]
    output: Json = {"systemMessage": "Round report\n" + "\n".join(shown)}

    message = str(payload.get("last_assistant_message") or "")
    unmentioned = [f for f in files if not path_mentioned(f, message, top)]
    if not payload.get("stop_hook_active") and (unmentioned or failures):
        output["decision"] = "block"
        output["reason"] = block_reason(unmentioned, failure_lines)
    return output


HANDLERS = {"log-failure": log_failure, "round-start": round_start, "round-end": round_end}


def main() -> None:
    """Dispatch the subcommand; a hook error is reported, never raised."""
    command = sys.argv[1]
    try:
        output = HANDLERS[command](cast("Json", json.load(sys.stdin)))
    except Exception as error:  # noqa: BLE001 - surface the hook's failure without blocking
        output = {"systemMessage": f"round-report {command} hook failed: {error!r}"}
    if output:
        sys.stdout.write(json.dumps(output) + "\n")


if __name__ == "__main__":
    main()
