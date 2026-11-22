# Copyright (c) 2026 Bad3r

"""PreToolUse hook that refuses a needless local `bash -c` or `sh -c` wrapper.

The Bash tool already runs bash, so a call that is one inline script handed to
a second shell adds nothing and hides its commands from the permission rules,
which match only the command text they can split. The deny reason tells the
agent to run the commands directly.

A wrapper is refused only as the leading command of the call, after any `cd`
or bare assignment, and only in its plain form: the shell, `-c`, and one inline
script. Everything that makes a second shell deliberate passes: a shell that
another program runs (timeout, xargs, find -exec, nix develop -c, ssh,
sbx exec), a login or interactive shell, zsh, a shell named by path, an
environment prefix, any other option, positional arguments after the script,
a script held in a variable, and a script that starts by sourcing a file.

The reader models plain words, quotes, simple expansions and redirections. A
call that uses anything else before its leading command ends (a substitution,
a here-document, a subshell, an array, an unclosed quote) passes unread.
"""

from __future__ import annotations

import json
import re
import sys
from typing import cast

SHELLS = ("bash", "sh")
WRAPPER_WORDS = 3
OPERATOR = re.compile(r"&&|\|\||;;|\|&|[;&|\n]")
SIMPLE_BRACES = re.compile(r"\$\{\w+\}")
REDIRECTION = re.compile(r"&>>?|<>|>>|>\||[<>]&?")
# Terminators after which the next command still leads the call.
SEQUENCE = frozenset({"&&", ";", "\n"})
# Characters of a special or positional parameter name.
PARAMETER_CHARS = frozenset("_@*#?!-")
REASON = (
    "`{shell} -c` wraps commands that this tool already runs in bash, and the "
    "permission checks cannot read inside the quoted script. Run the commands "
    "directly: `cd dir && cmd`, loops, pipes and `$VAR` work unwrapped, and "
    "`( ... )` keeps a `cd`, a `set -e`, a redirection or a pipe applying to all "
    "of them. Unrelated steps go in separate calls. In a REPL script, put the "
    "command text in the `$` template itself."
)


class UnmodelledError(Exception):
    """Shell syntax the reader does not model; the call then passes."""


class Reader:
    """Reads simple commands made of plain words, quotes and redirections."""

    def __init__(self, text: str) -> None:
        """Start at the beginning of the command text."""
        self.text = text
        self.pos = 0
        self.words: list[str] = []
        self.assignable: list[bool] = []
        self.word: list[str] | None = None
        self.quoted = False
        self.saw_equals = False
        self.assign_unquoted = True
        self.redirected = False
        self.skip_word = False
        self.handlers = {
            " ": self._blank,
            "\t": self._blank,
            "\\": self._escape,
            "'": self._single,
            '"': self._double,
            "$": self._dollar,
            "<": self._redirect,
            ">": self._redirect,
            "#": self._hash,
            "(": self._unmodelled,
            ")": self._unmodelled,
            "{": self._unmodelled,
            "`": self._unmodelled,
        }

    def command(self) -> tuple[list[str], list[bool], bool, str]:
        """Read one simple command: its words, assignability, whether it redirects, terminator."""
        self.words, self.assignable, self.redirected, self.skip_word = [], [], False, False
        while self.pos < len(self.text):
            operator = OPERATOR.match(self.text, self.pos)
            if self.text.startswith("&>", self.pos):
                self._redirect()
            elif operator:
                self._end_command()
                self.pos = operator.end()
                return self.words, self.assignable, self.redirected, operator[0]
            elif self.text[self.pos] in self.handlers:
                self.handlers[self.text[self.pos]]()
            else:
                if self.text[self.pos] == "=":
                    self.saw_equals = True
                self._add(self.text[self.pos])
                self.pos += 1
        self._end_command()
        return self.words, self.assignable, self.redirected, ""

    def _peek(self, offset: int = 1) -> str:
        return self.text[self.pos + offset : self.pos + offset + 1]

    def _add(self, piece: str) -> None:
        if self.word is None:
            self.word = []
        self.word.append(piece)

    def _mark_quoted(self) -> None:
        if not self.saw_equals:
            self.assign_unquoted = False
        self.quoted = True

    def _end_word(self) -> None:
        if self.word is not None and not self.skip_word:
            self.words.append("".join(self.word))
            self.assignable.append(self.assign_unquoted)
        if self.word is not None:
            self.skip_word = False
        self.word = None
        self.quoted = False
        self.saw_equals = False
        self.assign_unquoted = True

    def _end_command(self) -> None:
        self._end_word()
        if self.skip_word:
            raise UnmodelledError

    def _unmodelled(self) -> None:
        raise UnmodelledError

    def _blank(self) -> None:
        self._end_word()
        self.pos += 1

    def _hash(self) -> None:
        if self.word is not None:
            self._add("#")
            self.pos += 1
            return
        end = self.text.find("\n", self.pos)
        self.pos = len(self.text) if end < 0 else end

    def _escape(self) -> None:
        following = self._peek()
        if not following:
            raise UnmodelledError
        if following != "\n":
            self._mark_quoted()
            self._add(following)
        self.pos += 2

    def _single(self) -> None:
        end = self.text.find("'", self.pos + 1)
        if end < 0:
            raise UnmodelledError
        self._mark_quoted()
        self._add(self.text[self.pos + 1 : end])
        self.pos = end + 1

    def _double(self) -> None:
        self._mark_quoted()
        self._add("")
        self.pos += 1
        while self._peek(0) != '"':
            char = self._peek(0)
            if char in {"", "`"} or (char == "$" and self._peek() == "("):
                raise UnmodelledError
            if char == "\\":
                self._double_escape()
            elif char == "$":
                self._expansion()
            else:
                self._add(char)
                self.pos += 1
        self.pos += 1

    def _double_escape(self) -> None:
        following = self._peek()
        if not following:
            raise UnmodelledError
        if following in {"$", "`", '"', "\\"}:
            self._add(following)
        elif following != "\n":
            self._add("\\" + following)
        self.pos += 2

    def _dollar(self) -> None:
        if self._peek() in {"(", "'", '"'}:
            raise UnmodelledError
        self._expansion()

    def _expansion(self) -> None:
        braces = SIMPLE_BRACES.match(self.text, self.pos)
        if braces:
            self._add(braces[0])
            self.pos = braces.end()
        elif self._peek() == "{":
            raise UnmodelledError
        else:
            self._add("$")
            self.pos += 1

    def _redirect(self) -> None:
        operator = REDIRECTION.match(self.text, self.pos)
        if operator is None or self.text.startswith("<<", self.pos):
            raise UnmodelledError
        descriptor = "".join(self.word or [])
        if (
            operator[0][0] != "&"
            and not self.quoted
            and descriptor.isascii()
            and descriptor.isdigit()
        ):
            self.word = None
        self._end_word()
        self.pos = operator.end()
        if self._peek(0) in {"<", ">", "&", "|", "("}:
            raise UnmodelledError
        self.redirected = True
        self.skip_word = True


def is_assignment(word: str) -> bool:
    """Tell whether a word is a NAME=value or NAME+=value assignment."""
    name, equals, _ = word.partition("=")
    name = name.removesuffix("+")
    return bool(equals) and name.isascii() and name.isidentifier()


def is_prefix(words: list[str], assignable: list[bool]) -> bool:
    """Tell whether a simple command only sets up the one after it."""
    return words[0] == "cd" or all(
        ok and is_assignment(word) for word, ok in zip(words, assignable, strict=True)
    )


def is_deliberate(script: str) -> bool:
    """Tell whether a script is an option, a lone variable, empty, or sources a file first."""
    name = script.removeprefix("$").removeprefix("{").removesuffix("}")
    lone_variable = script.startswith("$") and bool(name)
    if script.startswith("-") or (
        lone_variable and all(c.isalnum() or c in PARAMETER_CHARS for c in name)
    ):
        return True
    lines = (line.strip() for line in script.split("\n"))
    first = next((line for line in lines if line and not line.startswith("#")), "")
    return not first or re.split(r"[\s<>]", first, maxsplit=1)[0] in {"source", "."}


def wrapper_shell(words: list[str]) -> str | None:
    """Return the shell name when a simple command is a needless -c wrapper."""
    plain = len(words) == WRAPPER_WORDS and words[0] in SHELLS and words[1] == "-c"
    return words[0] if plain and not is_deliberate(words[2]) else None


def needless_wrapper(command: str) -> str | None:
    """Return the shell name when the call's leading command is a needless wrapper."""
    reader = Reader(command)
    try:
        while True:
            words, assignable, redirected, terminator = reader.command()
            if words and not is_prefix(words, assignable):
                return wrapper_shell(words)
            blank = not words and not redirected
            if terminator not in (SEQUENCE if words else {"\n"} if blank else ()):
                return None
    except UnmodelledError:
        return None


def main() -> None:
    """Read a PreToolUse payload on stdin and print a deny decision if needed."""
    try:
        payload = cast("object", json.load(sys.stdin))
    except ValueError:
        return
    if not isinstance(payload, dict):
        return
    tool_input = cast("dict[str, object]", payload).get("tool_input")
    if not isinstance(tool_input, dict):
        return
    command = cast("dict[str, object]", tool_input).get("command")
    if not isinstance(command, str):
        return
    shell = needless_wrapper(command)
    if shell:
        decision = {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": REASON.format(shell=shell),
        }
        json.dump({"hookSpecificOutput": decision}, sys.stdout)


if __name__ == "__main__":
    main()
