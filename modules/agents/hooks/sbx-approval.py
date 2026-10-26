# Copyright (c) 2026 Bad3r
"""PreToolUse hook: sbx egress and the read-write shared directory need the owner.

Usage: sbx-approval.py ask|deny < payload. A guard rail over the command text:
a command built at runtime (variables naming sbx, interpreters, scripts) passes.
"""

import codecs
import json
import posixpath
import re
import shlex
import sys
from typing import NamedTuple, cast

EGRESS = "This sbx sandbox gets internet egress, so anything copied into it can leave the host."
SHARE = "This attaches the read-write shared directory, so the guest writes files on the host."
OPAQUE = "The approval hook cannot see this sbx call's arguments (sbx-mcp, stdin, or expansions)."
UNREADABLE = "The approval hook cannot read this tool call, so it fails closed."
TOO_DEEP = "The approval hook does not follow shell scripts nested this deep, so it fails closed."
STDIN = "A shell here reads a script the approval hook cannot see, and the call names sbx."
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
# Marks an unquoted expansion, brace, or glob, which can split into more words.
UNQUOTED = "\ue000"
EXPANSIONS = frozenset("${*?[")
# Each drops the word after it, its target, from the simple command.
REDIRECTS = frozenset({"<", ">", ">>", "<<", "<<<", ">&", "<&", "&>", "&>>", ">|", "<>"})
NON_LITERAL = re.compile(r"[$`{}*?\[]")
ANSI_C = re.compile(r"\$'((?:[^'\\]|\\.)*)'")
DOUBLE = re.compile(r'"((?:[^"\\]|\\.)*)"', re.DOTALL)
# Inside double quotes a backslash escapes only these, and it drops an escaped newline.
DOUBLE_ESCAPE = re.compile(r'\\([$`"\\\n])|[$`]')
# Options whose argument is a script: -c of any command, plus these after the named runner.
OPTION_WORD = re.compile(r"[-+][A-Za-z0-9-]*")
SCRIPT_OPTIONS = {"env": ("S", "--split-string"), "fish": ("C", "--init-command")}
# Shell options whose argument precedes the -c script.
SHELL_OPTION_ARGS = frozenset({"-o", "-O", "+o", "+O"})
STDIN_RUNNERS = frozenset({"xargs", "parallel"})
OPEN_VERBS = frozenset({"create", "run", "share"})
SHELLS = frozenset({"sh", "ash", "bash", "dash", "zsh", "ksh", "mksh", "fish"})
SOURCES = frozenset({"source", "."})
# Builtins and keywords that can precede source; external wrappers cannot run a builtin.
SOURCE_PREFIXES = frozenset(
    {"command", "builtin", "time", "!", "{", "if", "then", "else", "elif", "do", "while", "until"}
)
# Short shell options that take an argument; every other letter is a flag.
SHELL_ARG_LETTERS = {"fish": "CdDfop", "ksh": "oO" + "T", "mksh": "oO" + "T"}
SHELL_LONG_ARG = frozenset(
    {
        "--rcfile",
        "--init-file",
        "--init-command",
        "--profile",
        "--profile-startup",
        "--debug",
        "--debug-output",
        "--debug-stack-frames",
        "--features",
        "--emulate",
    }
)
SHELL_LONG_FLAGS = frozenset(
    {
        "--login",
        "--noprofile",
        "--norc",
        "--posix",
        "--restricted",
        "--verbose",
        "--version",
        "--help",
        "--debugger",
        "--dump-strings",
        "--dump-po-strings",
        "--noediting",
        "--pretty-print",
        "--interactive",
        "--private",
        "--no-execute",
        "--no-config",
        "--print-rusage-self",
        "--print-debug-categories",
    }
)
HEREDOC_END = frozenset(" \t\n;|&<>()")
COMMENT_AFTER = HEREDOC_END
# Delimiter, strip leading tabs, body is a shell script, body expands substitutions.
type Heredoc = tuple[str, bool, bool, bool]
# bash reads ${ to its first }, but $[ and (( count nested brackets.
NESTS = {"]": "[", ")": "("}
# bash joins a line continuation inside each of these openers.
SPLIT = re.compile(r"\$(?:\\\n)+[{[('\"]|\((?:\\\n)+\(|<(?:\\\n)+<")
MAX_DEPTH = 4
# Bounds the suffix checks per simple command, which are each linear.
MAX_CANDIDATES = 16
MAX_COMMAND = 64 * 1024


class GateError(Exception):
    """A call that needs the owner."""

    def __init__(self, reason: str) -> None:
        """Keep the reason the hook prints."""
        super().__init__(reason)
        self.reason = reason


def plain(text: str, index: int, out: list[str]) -> int:
    """Emit $'...' as plain single quoting and drop the $ of $"..."; return the index past it."""
    if text.startswith("$'", index):
        match = ANSI_C.match(text, index)
        if not match:
            msg = "unterminated $'"
            raise ValueError(msg)
        out.append(shlex.quote(codecs.decode(match[1], "unicode_escape")))
        return match.end()
    return index + text.startswith('$"', index)


def closing(text: str, start: int) -> int:
    """Return the index of the ) that closes the substitution body starting at start."""
    depth = 1
    quote = ""
    index = start
    while index < len(text):
        char = text[index]
        if char == "\\" and quote != "'":
            index += 2
            continue
        if quote == "'" or (quote == '"' and char not in '"$`'):
            quote = "" if char == quote else quote
        elif char == "$" and text.startswith("(", index + 1):
            index = closing(text, index + 2)
        elif char == "`":
            index = backtick_end(text, index + 1)
        elif char == "#" and text[index - 1] in COMMENT_AFTER:
            # A comment may hide the ), and a # inside ${ is not a comment.
            msg = "# in a substitution"
            raise ValueError(msg)
        elif char in "'\"":
            quote = "" if char == quote else char
        elif char in "()":
            depth += 1 if char == "(" else -1
            if depth == 0:
                return index
        index += 1
    msg = "unbalanced substitution"
    raise ValueError(msg)


def backtick_end(text: str, start: int) -> int:
    """Return the index of the backtick that ends the substitution starting at start."""
    index = start
    while index < len(text):
        if text[index] == "\\":
            index += 2
        elif text[index] == "`":
            return index
        else:
            index += 1
    msg = "unbalanced backtick"
    raise ValueError(msg)


def substitution(text: str, index: int, *, process: bool) -> tuple[str, int] | None:
    """Return the body of a substitution opening at index, and the index past it.

    process allows <(...) and >(...), which quotes and heredoc bodies keep literal.
    """
    if text[index] == "`":
        end = backtick_end(text, index + 1)
        return text[index + 1 : end].replace("\\`", "`"), end + 1
    opener = text[index] == "$" or (process and text[index] in "<>")
    if opener and text.startswith("(", index + 1):
        end = closing(text, index + 2)
        return text[index + 2 : end], end + 1
    return None


def unescape(escape: re.Match[str]) -> str:
    """Return the character a double-quote escape keeps; refuse a bare $ or backquote."""
    if escape[1] is None:
        msg = "heredoc delimiter with an expansion"
        raise ValueError(msg)
    return escape[1].strip("\n")


def delimiter_word(text: str, index: int) -> tuple[str, int, bool]:
    """Read a heredoc word at index; return it unquoted, the index past it, and its quoting."""
    parts: list[str] = []
    quoted = False
    while index < len(text) and text[index] not in HEREDOC_END:
        char = text[index]
        if text.startswith("\\\n", index):
            index += 2
            continue
        # bash reads $'...', $"...", $$, and expansions in the word as units.
        if char in "$`":
            msg = "heredoc delimiter with an expansion"
            raise ValueError(msg)
        if char not in "\\'\"":
            parts.append(char)
            index += 1
            continue
        quoted = True
        if char == "\\":
            parts.append(text[index + 1 : index + 2])
            index += 2
            continue
        if char == "'":
            end = text.index("'", index + 1)
            parts.append(text[index + 1 : end])
            index = end + 1
            continue
        match = DOUBLE.match(text, index)
        if not match:
            msg = "unterminated quote"
            raise ValueError(msg)
        parts.append(DOUBLE_ESCAPE.sub(unescape, match[1]))
        index = match.end()
    return "".join(parts), index, quoted


def heredoc(text: str, index: int) -> tuple[str, int, Heredoc]:
    """Read the << operator at index; return it requoted, the index past it, and its body."""
    start = index
    index += 2
    strip = text.startswith("-", index)
    index += strip
    while index < len(text) and (text[index] in " \t" or text.startswith("\\\n", index)):
        index += 1 + (text[index] == "\\")
    word_start = index
    delimiter, index, quoted = delimiter_word(text, index)
    if index == word_start:
        msg = "heredoc without a delimiter"
        raise ValueError(msg)
    line_end = text.find("\n", index)
    line = text[text.rfind("\n", 0, start) + 1 : len(text) if line_end == -1 else line_end]
    runners = SHELLS | SOURCES
    shell = any(basename(part) in runners for part in re.split(r"[\s;|&()]+", line))
    return "<<" + shlex.quote(delimiter), index, (delimiter, bool(strip), shell, not quoted)


def body_line(text: str, index: int, *, join: bool) -> tuple[str, int]:
    """Read one heredoc body line at index; return it and the index past its newline.

    An unquoted delimiter makes a trailing odd backslash join the next line, as in bash.
    """
    parts: list[str] = []
    while True:
        end = text.find("\n", index)
        end = len(text) if end == -1 else end
        line = text[index:end]
        index = end + 1
        trailing = len(line) - len(line.rstrip("\\"))
        if not (join and trailing % 2 and index <= len(text)):
            parts.append(line)
            return "".join(parts), index
        parts.append(line[:-1])


def bodies(text: str, index: int, pending: list[Heredoc], scripts: list[str]) -> int:
    """Consume the heredoc bodies after a newline, collecting what they run; return the end."""
    for delimiter, strip, shell, expands in pending:
        lines: list[str] = []
        while index < len(text):
            line, index = body_line(text, index, join=expands)
            if (line.lstrip("\t") if strip else line) == delimiter:
                break
            lines.append(line)
        body = "\n".join(lines)
        if shell:
            scripts.append(body)
        elif expands:
            scripts.extend(scan(body, heredoc_body=True)[1])
    return min(index, len(text))


def comment(text: str, index: int, out: list[str]) -> bool:
    """Whether an unquoted # at index starts a comment: it begins a word of the joined text.

    Only a lone separator or <<< emitted before it ends a word; an escaped separator does not.
    """
    last = out[-1] if out else ""
    separator = (len(last) == 1 and last in COMMENT_AFTER) or last == "<<<"
    return text[index] == "#" and (not out or separator)


def prelude(text: str, index: int, out: list[str], *, quote: str, process: bool) -> int:
    """Skip a comment or a line continuation, or emit $'...' plainly; return the index past it.

    A comment keeps its own backslash-newline and $'...' literal.
    """
    if process and comment(text, index, out):
        end = text.find("\n", index)
        return len(text) if end == -1 else end
    if quote != "'" and text.startswith("\\\n", index):
        return index + 2
    return plain(text, index, out) if process else index


def nest(
    text: str, index: int, quote: str, closers: list[tuple[str, str]], pending: list[Heredoc]
) -> int:
    """Open or close a ${, $[, or bare (( at index; return the index past an opener.

    bash reads these as text, where << is literal or a shift, and reads pending heredoc
    bodies only after a newline outside them.
    """
    opened = text[index : index + 2]
    if closers and not quote and (opened == "<<" or (pending and text[index] == "\n")):
        msg = "<< or a heredoc body inside ${, $[, or (("
        raise ValueError(msg)
    if quote != "'" and SPLIT.match(text, index):
        msg = "opener split by a line continuation"
        raise ValueError(msg)
    # Inside a double-quoted ${, single quotes quote too.
    if closers[-1:] == [("}", '"')] and quote == '"' and text[index] == "'":
        msg = "' inside a double-quoted ${"
        raise ValueError(msg)
    if opened in {"${", "$["} and quote != "'":
        closers.append(("}" if opened == "${" else "]", quote))
        return index + 2
    if opened == "((" and not quote:
        closers += [(")", "")] * 2
        return index + 2
    if closers and closers[-1][1] == quote:
        closer = closers[-1][0]
        if text[index] == closer:
            closers.pop()
        elif text[index] == NESTS.get(closer):
            closers.append(closers[-1])
    return index


def scan(text: str, *, heredoc_body: bool = False) -> tuple[str, list[str]]:
    """Cut heredoc bodies out of shell text; return it with the scripts its substitutions run.

    A heredoc body treats quotes as literal text and has no heredocs of its own.
    """
    out: list[str] = []
    scripts: list[str] = []
    pending: list[Heredoc] = []
    # Each open ${, $[, or bare ((: its closer and the quote it opened in.
    closers: list[tuple[str, str]] = []
    quote = ""
    index = 0
    while index < len(text):
        char = text[index]
        process = not quote and not heredoc_body
        # ${, $[, and (( have no comments, and $'...' never starts with #.
        mode = process and not (closers and char == "#")
        if (after := prelude(text, index, out, quote=quote, process=mode)) != index:
            index = after
            continue
        found = None if quote == "'" else substitution(text, index, process=process)
        if found:
            scripts.append(found[0])
            out.append(text[index : found[1]])
            index = found[1]
            continue
        step = 3 if text.startswith("<<<", index) else 2 if char == "\\" and quote != "'" else 0
        if step:
            out.append(text[index : index + step])
            index += step
            continue
        if not heredoc_body and (after := nest(text, index, quote, closers, pending)) != index:
            out.append(text[index:after])
            index = after
            continue
        if heredoc_body:
            pass
        elif char in "'\"" and quote in {"", char}:
            quote = "" if quote else char
        elif not quote and text.startswith("<<", index):
            operator, index, body = heredoc(text, index)
            out.append(operator)
            pending.append(body)
            continue
        elif char == "\n" and not quote and pending:
            out.append(char)
            index = bodies(text, index + 1, pending, scripts)
            pending = []
            continue
        out.append(char)
        index += 1
    return "".join(out), scripts


def words(command: str) -> list[str]:
    """Split shell text into words and operators; raise ValueError when it does not parse."""
    command = mark(command).replace("\n", " ; ")
    lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    lexer.commenters = ""
    return list(lexer)


def mark(command: str) -> str:
    """Prefix unquoted expansions with UNQUOTED; an unquoted backtick opens a substitution."""
    out: list[str] = []
    quote = ""
    escaped = False
    for char in command:
        if escaped:
            escaped = False
        elif char == "\\" and quote != "'":
            escaped = True
        elif char in "'\"" and quote in {"", char}:
            quote = "" if quote else char
        elif char == "`" and not quote:
            out.append(" ( ")
            continue
        elif char in EXPANSIONS and not quote:
            out.append(UNQUOTED)
        out.append(char)
    return "".join(out)


class Command(NamedTuple):
    """A simple command: its words, the operator ending it, and its literal stdin."""

    words: list[str]
    end: str
    herestrings: list[str]
    heredoc: bool


def segments(tokens: list[str]) -> list[Command]:
    """Split words into simple commands, dropping redirections but keeping here-strings."""
    result: list[Command] = []
    current = Command([], "", [], heredoc=False)
    target = ""
    for part in tokens:
        operator = bool(part) and set(part) <= OPERATORS
        if target and not operator:
            if target == "<<<":
                current.herestrings.append(part)
            target = ""
        elif part in REDIRECTS:
            target = part
            current = current._replace(heredoc=current.heredoc or part == "<<")
        elif operator:
            target = ""
            result.append(current._replace(end=part))
            current = Command([], "", [], heredoc=False)
        else:
            current.words.append(part)
    result.append(current)
    return result


def basename(word: str) -> str:
    """Return the last path component."""
    return word.rsplit("/", 1)[-1]


def mentions(text: str) -> bool:
    """Whether shell text could name sbx, sbx-mcp, or workloads."""
    bare = re.sub(r"[\"'\\]", "", text.replace("\\\n", ""))
    return "sbx" in bare or "workloads" in bare or "$'" in text.replace("\\\n", "")


def check(command: str, depth: int = 0) -> None:
    """Gate shell text and every script it runs, raising ValueError when it does not parse."""
    text, scripts = scan(command)
    for script in scripts:
        nested(script, depth)
    for simple in segments(words(text)):
        check_segment(simple.words, depth, cut="(" in simple.end)
        if reads_stdin(simple.words):
            for herestring in simple.herestrings:
                nested(herestring, depth)
            if not simple.herestrings and not simple.heredoc:
                raise GateError(STDIN)


def reads_stdin(segment: list[str]) -> bool:
    """Whether any shell or source in the command reads its script from stdin or a pipe.

    Every word naming a shell may be the real command (env SHELL=/bin/bash bash), so each counts.
    """
    command_position = True
    for index, word in enumerate(segment):
        name = basename(word)
        if name in SHELLS and shell_reads_stdin(name, segment[index + 1 :]):
            return True
        source = name in SOURCES and command_position
        operands = segment[index + 1 : index + 3]
        operand = operands[1:2] if operands[:1] == ["--"] else operands[:1]
        if source and (not operand or stdin_path(operand[0])):
            return True
        command_position = command_position and (
            word.startswith("-") or "=" in word or word in SOURCE_PREFIXES
        )
    return False


def shell_reads_stdin(shell: str, args: list[str]) -> bool:
    """Whether a shell given these arguments reads its script from stdin."""
    letters = SHELL_ARG_LETTERS.get(shell, "oO")
    index = 0
    while index < len(args) and args[index].startswith(("-", "+")):
        word = args[index]
        index += 1
        if word in {"-", "--"}:
            return word == "-" or index >= len(args) or stdin_path(args[index])
        if word.startswith("--"):
            option, equals, _ = word.partition("=")
            if option == "--command":
                return False
            if option not in SHELL_LONG_ARG | SHELL_LONG_FLAGS:
                raise GateError(OPAQUE)
            index += option in SHELL_LONG_ARG and not equals
            continue
        if "c" in word:
            return False
        if "s" in word:
            return True
        index += sum(letter in letters for letter in word[1:])
    return index >= len(args) or stdin_path(args[index])


def stdin_path(word: str) -> bool:
    """Whether a script operand may be stdin: -, or a path through a dev or proc directory."""
    parts = posixpath.normpath(word).split("/")
    return word == "-" or "dev" in parts or "proc" in parts


def nested(script: str, depth: int) -> None:
    """Gate a script that a substitution, heredoc, -c flag, or eval runs."""
    if depth < MAX_DEPTH:
        check(script, depth + 1)
    elif mentions(script):
        raise GateError(TOO_DEEP)


def check_segment(segment: list[str], depth: int, *, cut: bool) -> None:
    """Gate one simple command, cut short by a substitution if cut, and its -c or eval script.

    Any word naming sbx may start the real command (env A=/sbx sbx ...), so each one is checked.
    """
    stdin = evaluating = script = skip = False
    candidates = 0
    letters, longs = "c", {"--command"}
    for index, word in enumerate(segment):
        name = basename(word)
        candidates += candidate(name, segment[index + 1 :], stdin=stdin, cut=cut)
        if candidates > MAX_CANDIDATES:
            raise GateError(OPAQUE)
        if evaluating:
            nested(word, depth)
        elif skip:
            skip = False
        elif script and word in SHELL_OPTION_ARGS:
            skip = True
        elif script and not OPTION_WORD.fullmatch(word):
            script = False
            nested(word, depth)
        else:
            flag, attached = script_option(word, letters, longs)
            script = script or flag
            if attached is not None:
                nested(attached, depth)
        if name in SCRIPT_OPTIONS:
            letters += SCRIPT_OPTIONS[name][0]
            longs.add(SCRIPT_OPTIONS[name][1])
        stdin = stdin or name in STDIN_RUNNERS
        evaluating = evaluating or name == "eval"


def candidate(name: str, args: list[str], *, stdin: bool, cut: bool) -> bool:
    """Gate the command a word naming sbx, workloads, or sbx-mcp would start."""
    if name == "sbx-mcp":
        raise GateError(OPAQUE)
    if name not in {"sbx", "workloads"}:
        return False
    check_sbx(name, args, stdin=stdin, cut=cut)
    return True


def script_option(word: str, letters: str, longs: set[str]) -> tuple[bool, str | None]:
    """Whether word is a script option whose script is the next word, and any attached script."""
    option, equals, value = word.partition("=")
    if option in longs:
        return not equals, value if equals else None
    if word.startswith("--") or not word.startswith("-"):
        return False, None
    if word[1:].isalpha():
        return any(letter in word for letter in letters), None
    # env -S'sbx ...' attaches the script to the option letter.
    match = re.match(rf"-[A-Za-z]*?[{letters}](.+)", word, re.DOTALL)
    return False, match[1] if match else None


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


def check_split(args: list[str], positionals: list[str], *, stdin: bool, cut: bool) -> None:
    """Gate sbx arguments that a substitution, stdin, or word splitting could extend."""
    share = positionals[:1] == ["share"]
    if cut and (share or "--" not in args):
        raise GateError(OPAQUE)
    if positionals and positionals[0] not in OPEN_VERBS and not NON_LITERAL.search(positionals[0]):
        return
    if stdin:
        raise GateError(OPAQUE)
    head = args if share or "--" not in args else args[: args.index("--")]
    if any(UNQUOTED in word for word in head):
        raise GateError(OPAQUE)


def check_sbx(name: str, args: list[str], *, stdin: bool, cut: bool) -> None:
    """Check sbx or workloads options, which end at the first --."""
    positionals = positionals_of(args)
    check_split(args, positionals, stdin=stdin, cut=cut)
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


def review_mcp(tool: str, tool_input: object) -> None:
    """Gate an sbx MCP tool call."""
    if tool in {"mcp__sbx__create", "mcp__sbx__run"}:
        if field(tool_input, "net") not in (None, "none"):
            raise GateError(EGRESS)
    elif tool == "mcp__sbx__share_attach":
        share = field(tool_input, "share")
        if not isinstance(share, str) or share == "shared":
            raise GateError(SHARE)


def review(payload: object) -> None:
    """Gate one PreToolUse payload."""
    tool = field(payload, "tool_name")
    tool_input = field(payload, "tool_input")
    if not isinstance(tool, str):
        raise GateError(UNREADABLE)
    if tool != "Bash":
        review_mcp(tool, tool_input)
        return
    command = field(tool_input, "command")
    if not isinstance(command, str):
        raise GateError(UNREADABLE)
    if len(command) > MAX_COMMAND:
        raise GateError(TOO_LONG)
    # Every gate needs sbx, sbx-mcp, or workloads in the text.
    if not mentions(command):
        return
    try:
        check(command)
    except ValueError:
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
