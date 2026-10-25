# Copyright (c) 2026 Bad3r
"""PreToolUse hook: sbx egress and the read-write shared directory need the owner.

Usage: sbx-approval.py ask|deny < payload. A guard rail over the command text:
a command built at runtime (variables naming sbx, interpreters, scripts) passes.
"""

import codecs
import json
import re
import shlex
import sys
from typing import cast

EGRESS = "This sbx sandbox gets internet egress, so anything copied into it can leave the host."
SHARE = "This attaches the read-write shared directory, so the guest writes files on the host."
OPAQUE = "The approval hook cannot see this sbx call's arguments (sbx-mcp, stdin, or expansions)."
UNREADABLE = "The approval hook cannot read this tool call, so it fails closed."
TOO_DEEP = "The approval hook does not follow shell scripts nested this deep, so it fails closed."
TOO_LONG = "The approval hook does not parse commands over 64 KiB, so it fails closed."
CODEX = " Codex hooks cannot ask the owner, so hand them the exact command to run, or stay offline."

# argparse also takes a unique prefix of each.
VALUE_OPTIONS = (
    "--name",
    "--net",
    "--mem",
    "--cpus",
    "--ttl",
    "--wait",
    "--in",
    "--out",
    "--to",
    "--timeout",
)
OPERATORS = frozenset("();<>|&")
# Each drops the word after it, its target, from the simple command.
REDIRECTS = frozenset({"<", ">", ">>", "<<", "<<<", ">&", "<&", "&>", "&>>", ">|", "<>"})
NON_LITERAL = re.compile(r"[$`{}*?\[]")
ANSI_C = re.compile(r"\$'((?:[^'\\]|\\.)*)'")
SHELL_C = re.compile(r"-[A-Za-z]*c[A-Za-z]*")
# Shell options whose argument precedes the -c script.
SHELL_OPTION_ARGS = frozenset({"-o", "-O", "+o", "+O"})
STDIN_RUNNERS = frozenset({"xargs", "parallel"})
OPEN_VERBS = frozenset({"create", "run", "share"})
MAX_DEPTH = 4
MAX_COMMAND = 64 * 1024


class GateError(Exception):
    """A call that needs the owner."""

    def __init__(self, reason: str) -> None:
        """Keep the reason the hook prints."""
        super().__init__(reason)
        self.reason = reason


def words(command: str) -> list[str]:
    """Split shell text into words and operators; raise ValueError when it does not parse."""
    command = command.replace("\\\n", "")
    command = ANSI_C.sub(
        lambda match: shlex.quote(codecs.decode(match[1], "unicode_escape")), command
    )
    command = command.replace('$"', '"').replace("`", " ; ").replace("\n", " ; ")
    lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    lexer.commenters = ""
    return list(lexer)


def segments(tokens: list[str]) -> list[list[str]]:
    """Split words into simple commands at control operators, dropping redirections."""
    result: list[list[str]] = [[]]
    target = False
    for token in tokens:
        operator = bool(token) and set(token) <= OPERATORS
        if target and not operator:
            target = False
        elif token in REDIRECTS:
            target = True
        elif operator:
            target = False
            result.append([])
        else:
            result[-1].append(token)
    return result


def basename(word: str) -> str:
    """Return the last path component."""
    return word.rsplit("/", 1)[-1]


def check(command: str, depth: int = 0) -> None:
    """Gate shell text, raising ValueError when it does not parse."""
    for segment in segments(words(command)):
        check_segment(segment, depth)


def nested(script: str, depth: int) -> None:
    """Gate a script that a -c flag or eval runs."""
    if depth >= MAX_DEPTH:
        raise GateError(TOO_DEEP)
    check(script, depth + 1)


def check_segment(segment: list[str], depth: int) -> None:
    """Gate one simple command, and the script of a -c flag or eval."""
    stdin = evaluating = script = skip = False
    for index, word in enumerate(segment):
        name = basename(word)
        if name == "sbx-mcp":
            raise GateError(OPAQUE)
        if name in {"sbx", "workloads"}:
            check_sbx(name, segment[index + 1 :], stdin=stdin)
            return
        if evaluating:
            nested(word, depth)
        elif skip:
            skip = False
        elif script and word in SHELL_OPTION_ARGS:
            skip = True
        elif script and not word.startswith(("-", "+")):
            script = False
            nested(word, depth)
        elif SHELL_C.fullmatch(word):
            script = True
        stdin = stdin or name in STDIN_RUNNERS
        evaluating = evaluating or name == "eval"


def net_end(args: list[str], index: int, value: str | None) -> int:
    """Gate a --net other than none; return the index of its value."""
    if value is None:
        index += 1
        if index == len(args) or args[index] == "--":
            raise GateError(EGRESS)
        value = args[index]
    if value != "none":
        raise GateError(EGRESS)
    return index


def positionals_of(args: list[str]) -> list[str]:
    """Return the positionals before the first --, gating any egress option on the way."""
    positionals: list[str] = []
    index = 0
    while index < len(args):
        word = args[index]
        if word == "--":
            # argparse still reads share attach's name and tag past --; run's argv is the guest's.
            if positionals[:2] == ["share", "attach"]:
                positionals += args[index + 1 :]
            break
        option, equals, value = word.partition("=")
        if word.startswith("-") and NON_LITERAL.search(option):
            raise GateError(OPAQUE)
        if option in {"--ne", "--net"}:
            index = net_end(args, index, value if equals else None)
        elif word.startswith("--") and not equals:
            # argparse refuses an option word as the value, so it is never consumed.
            takes = any(known.startswith(option) for known in VALUE_OPTIONS)
            index += takes and index + 1 < len(args) and not args[index + 1].startswith("-")
        elif not word.startswith("-"):
            positionals.append(word)
        index += 1
    return positionals


def check_sbx(name: str, args: list[str], *, stdin: bool) -> None:
    """Check sbx or workloads options, which end at the first --."""
    positionals = positionals_of(args)
    if stdin and (not positionals or positionals[0] in OPEN_VERBS):
        raise GateError(OPAQUE)
    if positionals[:2] == ["share", "attach"]:
        # A redirection's fd number stays a word, so any word past the name may be the tag.
        operands = positionals[2:]
        sandbox = name == "sbx" or any(
            word.startswith("sbx-") or NON_LITERAL.search(word) for word in operands
        )
        tags = operands[1:]
        if sandbox and (not tags or any(t == "shared" or NON_LITERAL.search(t) for t in tags)):
            raise GateError(SHARE)
    elif name != "sbx":
        return
    elif positionals[:1] in (["create"], ["run"]):
        if any(NON_LITERAL.search(word) for word in positionals):
            raise GateError(OPAQUE)
    elif positionals and NON_LITERAL.search(positionals[0]):
        raise GateError(OPAQUE)


def field(mapping: object, key: str) -> object:
    """Read a key of a JSON object; anything else fails closed."""
    if not isinstance(mapping, dict):
        raise GateError(UNREADABLE)
    return cast("dict[str, object]", mapping).get(key)


def review(payload: object) -> None:
    """Gate one PreToolUse payload."""
    tool = field(payload, "tool_name")
    tool_input = field(payload, "tool_input")
    if not isinstance(tool, str):
        raise GateError(UNREADABLE)
    if tool in {"mcp__sbx__create", "mcp__sbx__run"}:
        if field(tool_input, "net") not in (None, "none"):
            raise GateError(EGRESS)
        return
    if tool != "Bash":
        return
    command = field(tool_input, "command")
    if not isinstance(command, str):
        raise GateError(UNREADABLE)
    if len(command) > MAX_COMMAND:
        raise GateError(TOO_LONG)
    try:
        check(command)
    except ValueError:
        # Unparsable text that could spell sbx fails closed; a heredoc with an apostrophe passes.
        if "sbx" in re.sub(r"[\"'\\]", "", command.replace("\\\n", "")) or "$'" in command:
            raise GateError(OPAQUE) from None


def main() -> int:
    """Print the decision for a gated call; print nothing to allow."""
    decision = sys.argv[1]
    try:
        review(json.load(sys.stdin))
    except GateError as gate:
        reason = gate.reason
    except ValueError, RecursionError:
        reason = UNREADABLE
    else:
        return 0
    if decision == "deny":
        reason += CODEX
    output = {
        "hookEventName": "PreToolUse",
        "permissionDecision": decision,
        "permissionDecisionReason": reason,
    }
    json.dump({"hookSpecificOutput": output}, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
