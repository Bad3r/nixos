# Copyright (c) 2026 Bad3r
"""Codex's web.run search service, answered from Kagi and locally fetched pages.

The output reproduces the service's own wording, failures included; the real
reasons behind a failure go only to the log file.
"""

from __future__ import annotations

import contextlib
import datetime as dt
import fcntl
import hashlib
import json
import os
import re
import sys
import tempfile
import time
import traceback
import urllib.parse
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING, Protocol, cast

from kagi_search import cli
from kagi_search.fetch import PDF_TYPE, FetchError, Page, fetch_page
from kagi_search.log import FILE_MODE, FileLog, private_directory, state_root
from kagi_search.page import filter_hits, matches_domain, normalize_domain
from kagi_search.render import Rendered, render
from kagi_search.run_schema import RUN_SCHEMA

if TYPE_CHECKING:
    from collections.abc import Callable, Generator

    from kagi_search.page import Hit

CITE_START = "\ue200"
CITE_END = "\ue201"
CITE_SEPARATOR = "\ue202"
BLOCK_SEPARATOR = "-" * 80 + "\n"
WORD_LIMIT = 200

# The service answers short with ~30 brief results and long with ~12 results
# carrying page text; Kagi's one results page holds about 30 hits and no page
# text, so the length scales the hit count and long rarely exceeds medium.
HITS_PER_LENGTH = {"short": 20, "medium": 30, "long": 40}
DEFAULT_LENGTH = "short"
DEFAULT_MAX_OUTPUT_TOKENS = 10_000
CHARS_PER_TOKEN = 4
MIN_VIEW_CHARS = 2_000
FIND_CONTEXT_LINES = 2

# Codex kills the program after 180 s; the response must be out well before.
CALL_DEADLINE_SECONDS = 150.0
PAGE_START_MARGIN_SECONDS = 10.0
SEARCH_START_MARGIN_SECONDS = 30.0

STATE_VERSION = 1
STATE_NAME_CHARS = 64
STATE_MAX_AGE = dt.timedelta(days=30)
LOCK_FLAGS = os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC
MAX_UTC_OFFSET_HOURS = 14
MINUTES_PER_HOUR = 60
HOURS_PER_HALF_DAY = 12

FAILURE_EXIT = 1

# The service's own wording, reproduced byte for byte.
SERVICE_UNAVAILABLE = "http 503 Service Unavailable: None"
NO_TOOL_RESPONSE = (
    "Found no tool response. This likely means the arguments you provided were not valid."
)
EMPTY_SEARCH = "Empty search results\nNo results were found for the provided queries"
UNKNOWN_REF = (
    "ClientResponseError\n500, message='Internal Server Error', "
    "url='http://search.openai.svc.cluster.local.:8000/internal/tool_call/process_stateless'"
)
INTERNAL_ERROR = "Internal Error"
CLICK_INVALID = "Unable to resolve click call due to invalid arguments"
SCREENSHOT_NOT_PDF = (
    "Unable to resolve screenshot call because content type is not application/pdf "
    "and web screenshot is not enabled"
)
NO_READABLE_LINES = "This page has no readable lines."
SCHEMA_ERROR = (
    "Error parsing function call: Invalid function_name='run' call: kwargs={}. Expected: "
)
MONTHS = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
NARROW_NO_BREAK_SPACE = "\u202f"

PAGE_KINDS = frozenset({"open", "click", "find", "screenshot"})


class RequestError(Exception):
    """The request is not a SearchRequest this emulator understands."""


class StateError(Exception):
    """The session state file cannot be used."""


class Searcher(Protocol):
    """Kagi search as cli.run offers it."""

    def __call__(
        self,
        query: str,
        *,
        allowed: list[str] | None,
        blocked: list[str] | None,
        limit: int,
        since: dt.date | None,
    ) -> list[Hit]:
        """Return the hits for the query, from pages Kagi dates since that day if given."""
        ...


@dataclass(frozen=True)
class Ref:
    """What a ref_id points at: a URL, its title, and its link table once viewed."""

    url: str
    title: str
    links: list[str] | None = None


@dataclass(frozen=True)
class Query:
    """One search_query entry."""

    q: str
    domains: list[str] | None
    recency: int | None = None


@dataclass(frozen=True)
class Operation:
    """One open, click, find, or screenshot entry."""

    kind: str
    ref_id: str
    lineno: int | None = None
    link: int = 0
    pattern: str = ""
    pageno: int = 0

    def source(self) -> str:
        """Return the call as the service's Source field shows it."""
        fields: dict[str, object] = {"ref_id": self.ref_id}
        if self.kind == "open":
            fields["lineno"] = self.lineno
        elif self.kind == "click":
            fields["id"] = self.link
        elif self.kind == "find":
            fields["pattern"] = self.pattern
        else:
            fields |= {"pageno": self.pageno, "height": None, "offset": None}
        return f"{self.kind}({json.dumps(fields, separators=(',', ':'), ensure_ascii=False)})"


@dataclass(frozen=True)
class Group:
    """One command of the request, in the order the request lists it."""

    key: str
    queries: list[Query] = field(default_factory=list[Query])
    operations: list[Operation] = field(default_factory=list[Operation])
    offsets: list[str] = field(default_factory=list[str])


@dataclass(frozen=True)
class Request:
    """The parts of a SearchRequest the emulator acts on."""

    session: str
    commands: dict[str, object]
    groups: list[Group]
    length: str
    max_output_tokens: int
    allowed: list[str] | None
    blocked: list[str] | None


# Request parsing


def _object(value: object, what: str) -> dict[str, object]:
    if not isinstance(value, dict):
        msg = f"{what} is not a JSON object"
        raise RequestError(msg)
    return cast("dict[str, object]", value)


def _entries(commands: dict[str, object], key: str) -> list[dict[str, object]]:
    value = commands.get(key)
    if value is None:
        return []
    if not isinstance(value, list):
        msg = f"commands.{key} is not a list"
        raise RequestError(msg)
    return [_object(item, f"an entry of commands.{key}") for item in cast("list[object]", value)]


def _string(entry: dict[str, object], key: str, where: str) -> str:
    value = entry.get(key)
    if not isinstance(value, str):
        msg = f"{where}.{key} is not a string"
        raise RequestError(msg)
    return value


def _integer(entry: dict[str, object], key: str, where: str) -> int | None:
    value = entry.get(key)
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        msg = f"{where}.{key} is not a non-negative integer"
        raise RequestError(msg)
    return value


def _required_integer(entry: dict[str, object], key: str, where: str) -> int:
    value = _integer(entry, key, where)
    if value is None:
        msg = f"{where}.{key} is missing"
        raise RequestError(msg)
    return value


def _strings(value: object, where: str) -> list[str] | None:
    if value is None:
        return None
    if not isinstance(value, list) or not all(
        isinstance(item, str) for item in cast("list[object]", value)
    ):
        msg = f"{where} is not a list of strings"
        raise RequestError(msg)
    return cast("list[str]", value)


def _operation(kind: str, entry: dict[str, object]) -> Operation:
    ref = _string(entry, "ref_id", kind)
    if kind == "open":
        return Operation(kind, ref, lineno=_integer(entry, "lineno", kind))
    if kind == "click":
        return Operation(kind, ref, link=_required_integer(entry, "id", kind))
    if kind == "find":
        return Operation(kind, ref, pattern=_string(entry, "pattern", kind))
    return Operation(kind, ref, pageno=_required_integer(entry, "pageno", kind))


def _group(commands: dict[str, object], key: str) -> Group:
    entries = _entries(commands, key)
    if key == "search_query":
        queries = [
            Query(
                _string(entry, "q", key),
                _strings(entry.get("domains"), "domains"),
                _integer(entry, "recency", key),
            )
            for entry in entries
        ]
        return Group(key, queries=queries)
    if key in PAGE_KINDS:
        return Group(key, operations=[_operation(key, entry) for entry in entries])
    if key == "time":
        return Group(key, offsets=[_string(entry, "utc_offset", key) for entry in entries])
    return Group(key)


def parse_request(value: object) -> Request:
    """Return the request's commands, in the order it lists them, and its settings."""
    request = _object(value, "the request")
    session = _string(request, "id", "request")
    commands = _object(request.get("commands"), "request.commands")
    groups = [_group(commands, key) for key in commands if key != "response_length"]
    length = commands.get("response_length", DEFAULT_LENGTH)
    if not isinstance(length, str) or length not in HITS_PER_LENGTH:
        msg = f"commands.response_length is not one of {', '.join(HITS_PER_LENGTH)}"
        raise RequestError(msg)
    tokens = _integer(request, "max_output_tokens", "request") or DEFAULT_MAX_OUTPUT_TOKENS
    filters: dict[str, object] = {}
    settings = request.get("settings")
    if settings is not None:
        found = _object(settings, "request.settings").get("filters")
        if found is not None:
            filters = _object(found, "request.settings.filters")
    return Request(
        session=session,
        commands=commands,
        groups=groups,
        length=length,
        max_output_tokens=tokens,
        allowed=_strings(filters.get("allowed_domains"), "allowed_domains"),
        blocked=_strings(filters.get("blocked_domains"), "blocked_domains"),
    )


def schema_violation(commands: dict[str, object]) -> bool:
    """Tell whether the service's own schema rejects the call: sports needs tool "sports"."""
    return any(entry.get("tool") != "sports" for entry in _entries(commands, "sports"))


# Session state


def state_directory() -> Path:
    """Return the directory holding one state file per web.run session."""
    return state_root() / "web-run"


def state_name(session: str) -> str:
    """Return a file name for the session id that stays inside the state directory."""
    readable = re.sub(r"[^A-Za-z0-9_-]", "_", session)[:STATE_NAME_CHARS] or "session"
    digest = hashlib.sha256(session.encode("utf-8", "surrogatepass")).hexdigest()[:16]
    return f"{readable}-{digest}"


def _ref(value: object) -> Ref:
    entry = _object(value, "a stored ref")
    links = entry.get("links")
    return Ref(
        url=_string(entry, "url", "ref"),
        title=_string(entry, "title", "ref"),
        links=_strings(links, "ref.links"),
    )


@dataclass
class State:
    """A session's turn counter and the refs its earlier turns handed out."""

    turn: int = 0
    refs: dict[str, Ref] = field(default_factory=dict[str, Ref])

    @classmethod
    def load(cls, path: Path) -> State:
        """Read the state file, or return a fresh state when there is none."""
        try:
            text = path.read_text(encoding="utf-8")
        except FileNotFoundError:
            return cls()
        try:
            return cls._parse(text)
        except (ValueError, RequestError) as error:
            msg = f"web.run state {path} is unreadable ({error}); delete it to reset the session"
            raise StateError(msg) from None

    @classmethod
    def _parse(cls, text: str) -> State:
        data = _object(json.loads(text), "the state")
        turn = data.get("turn")
        if data.get("version") != STATE_VERSION or not isinstance(turn, int):
            msg = "unknown version or turn"
            raise RequestError(msg)
        refs = _object(data.get("refs"), "refs")
        return cls(turn, {key: _ref(value) for key, value in refs.items()})

    def dump(self) -> str:
        """Return the state as JSON."""
        refs: dict[str, dict[str, object]] = {}
        for key, ref in self.refs.items():
            entry: dict[str, object] = {"url": ref.url, "title": ref.title}
            if ref.links is not None:
                entry["links"] = ref.links
            refs[key] = entry
        return json.dumps({"version": STATE_VERSION, "turn": self.turn, "refs": refs})


def _same_file(descriptor: int, path: Path) -> bool:
    try:
        current = path.lstat()
    except FileNotFoundError:
        return False
    held = os.fstat(descriptor)
    return (held.st_dev, held.st_ino) == (current.st_dev, current.st_ino)


def _acquire(path: Path, operation: int) -> int | None:
    """Return a descriptor holding the flock on path, or None when it is busy.

    Pruning unlinks lock files, so a lock only counts while path still names the
    locked file; otherwise the caller retries on the file now at path.
    """
    while True:
        descriptor = os.open(path, LOCK_FLAGS, FILE_MODE)
        try:
            fcntl.flock(descriptor, operation)
        except BlockingIOError:
            os.close(descriptor)
            return None
        except BaseException:
            os.close(descriptor)
            raise
        if _same_file(descriptor, path):
            return descriptor
        os.close(descriptor)


def _older(path: Path, cutoff: float) -> bool:
    try:
        return path.lstat().st_mtime < cutoff
    except FileNotFoundError:
        return False


def _prune_session(state: Path, lock: Path, cutoff: float) -> None:
    """Delete a session's state and lock files once its state is older than cutoff."""
    if not (_older(state, cutoff) or (not state.exists() and _older(lock, cutoff))):
        return
    descriptor = _acquire(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    if descriptor is None:
        return
    try:
        if _older(state, cutoff) or not state.exists():
            state.unlink(missing_ok=True)
            lock.unlink(missing_ok=True)
    finally:
        os.close(descriptor)


class Session:
    """A web.run session's state file, guarded by an flock."""

    def __init__(self, directory: Path, session: str) -> None:
        """Place the session's state and lock files in the directory."""
        self.directory = directory
        name = state_name(session)
        self.path = directory / f"{name}.json"
        self.lock_path = directory / f"{name}.lock"

    @contextlib.contextmanager
    def _locked(self) -> Generator[None]:
        private_directory(self.directory.parent, self.directory)
        descriptor = _acquire(self.lock_path, fcntl.LOCK_EX)
        if descriptor is None:
            msg = f"cannot lock {self.lock_path}"
            raise StateError(msg)
        try:
            yield
        finally:
            os.close(descriptor)

    def _save(self, state: State) -> None:
        descriptor, temporary = tempfile.mkstemp(
            dir=self.directory, prefix=f".{self.path.name}.", suffix=".tmp"
        )
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
                handle.write(state.dump())
                handle.flush()
                os.fsync(handle.fileno())
            Path(temporary).replace(self.path)
        except BaseException:
            Path(temporary).unlink(missing_ok=True)
            raise

    def begin(self) -> tuple[int, dict[str, Ref]]:
        """Claim the next turn number and return it with the refs known so far."""
        with self._locked():
            state = State.load(self.path)
            turn = state.turn
            state.turn += 1
            self._save(state)
        return turn, state.refs

    def prune(self, now: dt.datetime) -> None:
        """Delete other sessions whose state was last written over STATE_MAX_AGE ago."""
        cutoff = (now - STATE_MAX_AGE).timestamp()
        mine = {self.path.name, self.lock_path.name}
        for path in sorted(self.directory.iterdir()):
            if path.name in mine:
                continue
            if path.suffix in {".json", ".lock"} and not path.name.startswith("."):
                _prune_session(path.with_suffix(".json"), path.with_suffix(".lock"), cutoff)
            elif path.name.startswith(".") and path.suffix == ".tmp" and _older(path, cutoff):
                path.unlink(missing_ok=True)

    def record(self, refs: dict[str, Ref]) -> None:
        """Add the refs one call handed out."""
        if not refs:
            return
        with self._locked():
            state = State.load(self.path)
            state.refs.update(refs)
            self._save(state)


# Output


def cite(ref_id: str) -> str:
    """Return the citation marker the service puts before a result."""
    return f"{CITE_START}cite{CITE_SEPARATOR}{ref_id}{CITE_END}"


def domain_of(url: str) -> str:
    """Return the URL's host name."""
    return urllib.parse.urlsplit(url).hostname or ""


def text_result(ref_id: str, url: str, title: str, snippet: str) -> dict[str, object]:
    """Return a results entry in the service's shape; a page without a title has none."""
    entry: dict[str, object] = {
        "type": "text_result",
        "domain": domain_of(url),
        "ref_id": ref_id,
        "snippet": snippet,
    }
    if title:
        entry["title"] = title
    entry["url"] = url
    return entry


def error_result(ref_id: str, snippet: str | None = None) -> dict[str, object]:
    """Return the results entry the service gives an Internal Error block."""
    entry: dict[str, object] = {"type": "text_result", "ref_id": ref_id}
    if snippet is not None:
        entry["snippet"] = snippet
    entry["title"] = INTERNAL_ERROR
    return entry


def search_block(hit: Hit, ref_id: str) -> str:
    """Return one search hit as the service lays it out."""
    return f"{hit.title} ({hit.url})\n{cite(ref_id)} {_wordlim(hit.snippet)}\n"


def _wordlim(rest: str) -> str:
    return f"[wordlim: {WORD_LIMIT}] {rest}".rstrip()


def not_accessible_block(ref_id: str, source: str, url: str) -> str:
    """Return the service's block for a page it could not fetch."""
    return (
        f"{INTERNAL_ERROR} ()\n{cite(ref_id)} [wordlim: {WORD_LIMIT}] Source: {source}; \n"
        f"URL {url} is not accessible via this tool."
    )


def failed_fetch_block(ref_id: str, source: str, url: str) -> str:
    """Return the service's block for a PDF page it could not take a screenshot of."""
    return (
        f"{INTERNAL_ERROR} ()\n{cite(ref_id)} [wordlim: {WORD_LIMIT}] Source: {source}; \n"
        f"Failed to fetch {url}: {INTERNAL_ERROR}"
    )


def invalid_call_block(ref_id: str, message: str) -> str:
    """Return the service's block for a call it cannot resolve."""
    return f"{INTERNAL_ERROR} ()\n{cite(ref_id)} [wordlim: {WORD_LIMIT}] {message}\nL0: {message}\n"


def _numbered(index: int, line: str) -> str:
    return f"L{index}: {line}\n"


def window(lines: list[str], start: int, budget: int) -> range:
    """Return the line range shown from start within budget characters.

    The window runs forward from start and, when the page ends first, grows backward.
    """
    if not lines:
        return range(0)
    start = min(max(start, 0), len(lines) - 1)
    used = len(_numbered(start, lines[start]))
    end = start + 1
    while end < len(lines) and used + len(_numbered(end, lines[end])) <= budget:
        used += len(_numbered(end, lines[end]))
        end += 1
    while end == len(lines) and start > 0:
        if used + len(_numbered(start - 1, lines[start - 1])) > budget:
            break
        start -= 1
        used += len(_numbered(start, lines[start]))
    return range(start, end)


def _fit(text: str, budget: int) -> str:
    return text if len(text) <= budget else text[: max(budget - 1, 0)] + "\n"


def view_header(page: Page, title: str, ref_id: str, source: str, total: int) -> str:
    """Return the two header lines of a page view."""
    redirect = f" Redirected to URL: {page.url};" if page.redirected else ""
    details = (
        f"Crawled: today; Content type: {page.content_type}; Source: {source};"
        f"{redirect} Total lines: {total}"
    )
    return f"{title} ({page.url})\n{cite(ref_id)} {_wordlim(details)}\n"


def view_body(lines: list[str], shown: range | list[int], budget: int) -> str:
    """Return the shown lines, numbered, cut to budget characters at a line boundary."""
    out: list[str] = []
    used = 0
    for index in shown:
        numbered = _numbered(index, lines[index])
        if out and used + len(numbered) > budget:
            break
        out.append(_fit(numbered, budget - used))
        used += len(numbered)
    return "".join(out)


def find_lines(lines: list[str], pattern: str) -> list[int]:
    """Return the indexes of the lines matching the pattern, with context lines."""
    needle = pattern.casefold()
    shown: set[int] = set()
    for index, line in enumerate(lines):
        if needle in line.casefold():
            low = max(index - FIND_CONTEXT_LINES, 0)
            high = min(index + FIND_CONTEXT_LINES + 1, len(lines))
            shown.update(range(low, high))
    return sorted(shown)


def join_blocks(blocks: list[str]) -> str:
    """Join operation outputs as the service does: each separator follows its block directly."""
    return BLOCK_SEPARATOR.join(blocks)


def _trim(block: str, room: int) -> str:
    """Return the block's leading whole lines that fit in room characters."""
    if len(block) <= room:
        return block
    if room <= 0:
        return ""
    cut = block.rfind("\n", 0, room)
    return block[: cut + 1] if cut > 0 else ""


def fit_blocks(blocks: list[str], budget: int) -> str:
    """Join the blocks within budget characters, in order.

    The first block that does not fit is cut to whole lines and the blocks after
    it are left out, silently, as the service truncates.
    """
    kept: list[str] = []
    for block in blocks:
        if len(join_blocks([*kept, block])) <= budget:
            kept.append(block)
            continue
        trimmed = _trim(block, budget - len(join_blocks([*kept, ""])))
        if trimmed:
            kept.append(trimmed)
        break
    return join_blocks(kept)[:budget]


def utc_offset(text: str) -> dt.timedelta | None:
    """Return the offset a "+03:00" style string names, or None if it names none."""
    match = re.fullmatch(r"([+-])(\d{1,2})(?::?(\d{2}))?", text.strip())
    if not match:
        return None
    hours, minutes = int(match[2]), int(match[3] or 0)
    if hours > MAX_UTC_OFFSET_HOURS or minutes >= MINUTES_PER_HOUR:
        return None
    sign = -1 if match[1] == "-" else 1
    return sign * dt.timedelta(hours=hours, minutes=minutes)


def time_text(delta: dt.timedelta, now: dt.datetime) -> str:
    """Return the service's sentence for the time at the UTC offset."""
    local = now.astimezone(dt.timezone(delta))
    label = local.strftime("%z")
    hour = local.hour % HOURS_PER_HALF_DAY or HOURS_PER_HALF_DAY
    meridiem = "AM" if local.hour < HOURS_PER_HALF_DAY else "PM"
    stamp = (
        f"{MONTHS[local.month - 1]} {local.day}, {local.year}, "
        f"{hour}:{local:%M:%S}{NARROW_NO_BREAK_SPACE}{meridiem}"
    )
    return f"The time in UTC{label[:3]}:{label[3:]} is {stamp}"


# The call


@dataclass
class _Call:
    """One web.run call: its turn, known refs, and what it produced."""

    turn: int
    refs: dict[str, Ref]
    fetch: Callable[[str, float], Page]
    today: dt.date
    log: Callable[[str], None]
    deadline: float
    blocks: list[str] = field(default_factory=list[str])
    results: list[dict[str, object]] = field(default_factory=list[dict[str, object]])
    new_refs: dict[str, Ref] = field(default_factory=dict[str, Ref])
    pages: dict[str, Page | FetchError] = field(default_factory=dict[str, Page | FetchError])
    counts: dict[str, int] = field(default_factory=dict[str, int])

    def next_id(self, kind: str) -> str:
        """Return the next ref_id of the kind (search, view, time) in this turn."""
        count = self.counts.get(kind, 0)
        self.counts[kind] = count + 1
        return f"turn{self.turn}{kind}{count}"

    def get(self, url: str) -> Page:
        """Fetch the page once per call, within the call's deadline."""
        cached = self.pages.get(url)
        if cached is None:
            try:
                cached = self._fetch(url)
            except FetchError as error:
                cached = error
            except Exception as error:  # noqa: BLE001 - a fetch bug costs one page, not the call
                cached = FetchError(f"unexpected {type(error).__name__}: {error}")
                self.log(f"fetching {url} failed\n{''.join(traceback.format_exception(error))}")
            self.pages[url] = cached
        if isinstance(cached, FetchError):
            raise cached
        return cached

    def _fetch(self, url: str) -> Page:
        if time.monotonic() > self.deadline - PAGE_START_MARGIN_SECONDS:
            msg = f"not started: the call's {CALL_DEADLINE_SECONDS:g} s deadline is near"
            raise FetchError(msg)
        return self.fetch(url, self.deadline - PAGE_START_MARGIN_SECONDS)

    def lookup(self, ref_id: str) -> Ref | None:
        """Return what the ref_id points at, from this call or earlier ones."""
        return self.new_refs.get(ref_id) or self.refs.get(ref_id)

    def target(self, ref_id: str) -> tuple[str, Ref | None] | None:
        """Return the URL a ref_id or literal URL names, or None for an unknown ref_id."""
        ref = self.lookup(ref_id)
        if ref is not None:
            return ref.url, ref
        if "://" in ref_id:
            return ref_id, None
        if re.fullmatch(r"[A-Za-z0-9.-]+\.[A-Za-z]{2,}(?::\d+)?(?:[/?#]\S*)?", ref_id):
            return f"https://{ref_id}", None
        return None


def allowed_domains(configured: list[str] | None, requested: list[str] | None) -> list[str] | None:
    """Return the domains a hit may come from under both lists, or None for any domain.

    Each pair keeps the narrower domain when one contains the other; an empty
    list means the two lists share no domain.
    """
    allow = [d for d in map(normalize_domain, configured or []) if d]
    want = [d for d in map(normalize_domain, requested or []) if d]
    if not allow or not want:
        return allow or want or None
    narrowed: list[str] = []
    for outer in allow:
        for inner in want:
            if matches_domain(inner, outer):
                narrowed.append(inner)
            elif matches_domain(outer, inner):
                narrowed.append(outer)
    return list(dict.fromkeys(narrowed))


def _query(call: _Call, request: Request, search: Searcher, query: Query) -> list[Hit]:
    """Return the query's hits; a query that cannot match anything contributes none."""
    if not query.q.strip():
        return []
    allowed = allowed_domains(request.allowed, query.domains)
    if allowed == []:
        call.log(f"search {query.q!r}: none of its domains is an allowed domain")
        return []
    if time.monotonic() > call.deadline - SEARCH_START_MARGIN_SECONDS:
        call.log(f"search {query.q!r}: not started, the call's deadline is near")
        return []
    since = None if query.recency is None else call.today - dt.timedelta(days=query.recency)
    hits = search(
        query.q,
        allowed=allowed,
        blocked=request.blocked,
        limit=HITS_PER_LENGTH[request.length],
        since=since,
    )
    return filter_hits(hits, allowed, request.blocked)


def _search(call: _Call, request: Request, search: Searcher, group: Group) -> None:
    found = False
    for query in group.queries:
        for hit in _query(call, request, search, query):
            found = True
            ref_id = call.next_id("search")
            call.blocks.append(search_block(hit, ref_id))
            call.results.append(text_result(ref_id, hit.url, hit.title, hit.snippet))
            call.new_refs[ref_id] = Ref(hit.url, hit.title)
    if not found:
        call.blocks.append(EMPTY_SEARCH)


def _not_accessible(call: _Call, ref_id: str, source: str, url: str, error: Exception) -> None:
    call.log(f"{source}: {url} is not accessible: {error}")
    call.blocks.append(not_accessible_block(ref_id, source, url))
    call.results.append(error_result(ref_id))


def _view(call: _Call, operation: Operation, budget: int) -> None:
    source = operation.source()
    ref_id = call.next_id("view")
    found = call.target(operation.ref_id)
    if found is None:
        msg = f"unknown ref_id {operation.ref_id!r}"
        raise RequestError(msg)
    url, ref = found
    try:
        if operation.kind == "click":
            links = ref.links if ref is not None and ref.links is not None else None
            if links is None:
                links = render(call.get(url)).links
            if operation.link >= len(links):
                call.log(f"{source}: {url} has {len(links)} links")
                call.blocks.append(invalid_call_block(ref_id, CLICK_INVALID))
                call.results.append(error_result(ref_id, CLICK_INVALID))
                return
            url, ref = links[operation.link], None
        page = call.get(url)
    except FetchError as error:
        _not_accessible(call, ref_id, source, url, error)
        return
    if operation.kind == "screenshot":
        _screenshot(call, operation, page, ref_id)
        return
    if page.content_type == PDF_TYPE:
        _not_accessible(call, ref_id, source, url, FetchError("PDF text cannot be read"))
        return
    rendered = render(page) if page.body is not None else None
    if rendered is None or not rendered.lines:
        title = rendered.title if rendered else ""
        call.blocks.append(f"{title} ({page.url})\n{cite(ref_id)} {NO_READABLE_LINES}")
        return
    _show(call, operation, page, rendered=rendered, ref_id=ref_id, ref=ref, budget=budget)


def _show(  # noqa: PLR0913 - the parts of one page view
    call: _Call,
    operation: Operation,
    page: Page,
    *,
    rendered: Rendered,
    ref_id: str,
    ref: Ref | None,
    budget: int,
) -> None:
    title = rendered.title or (ref.title if ref else "")
    total = len(rendered.lines)
    header = view_header(page, title, ref_id, operation.source(), total)
    room = max(budget - len(header), 0)
    if operation.kind == "find":
        shown = find_lines(rendered.lines, operation.pattern)
        if shown:
            call.blocks.append(header + view_body(rendered.lines, shown, room))
        else:
            call.blocks.append(f'{header}No matching text found for "{operation.pattern}"')
    else:
        shown_range = window(rendered.lines, operation.lineno or 0, room)
        call.blocks.append(header + view_body(rendered.lines, shown_range, room))
    call.results.append(text_result(ref_id, page.url, title, f"Total lines: {total}"))
    call.new_refs[ref_id] = Ref(page.url, title, rendered.links)


def _screenshot(call: _Call, operation: Operation, page: Page, ref_id: str) -> None:
    source = operation.source()
    if page.content_type != PDF_TYPE:
        call.blocks.append(invalid_call_block(ref_id, SCREENSHOT_NOT_PDF))
        call.results.append(error_result(ref_id, SCREENSHOT_NOT_PDF))
        return
    if page.pdf_pages is not None and operation.pageno >= page.pdf_pages:
        call.log(f"{source}: {page.url} has {page.pdf_pages} pages")
        call.blocks.append(failed_fetch_block(ref_id, source, page.url))
        call.results.append(error_result(ref_id))
        return
    call.log(f"{source}: PDF pages cannot be rendered to images; answered without one")
    call.blocks.append(f" ({page.url})\n{cite(ref_id)} ")


def _time(call: _Call, group: Group, now: dt.datetime) -> None:
    for offset in group.offsets:
        delta = utc_offset(offset)
        if delta is None:
            call.log(f"time: {offset!r} is not a UTC offset")
            continue
        call.blocks.append(f"{cite(call.next_id('time'))} {time_text(delta, now)}")


def _unknown_ref(call: _Call, request: Request) -> str | None:
    for group in request.groups:
        for operation in group.operations:
            if call.target(operation.ref_id) is None:
                return operation.ref_id
    return None


def _page_budget(call: _Call, budget: int, operations_left: int) -> int:
    room = budget - len(join_blocks([*call.blocks, ""]))
    return max(min(max(room // operations_left, MIN_VIEW_CHARS), room), 0)


def handle(  # noqa: PLR0913 - the call's collaborators, injected for tests
    value: object,
    *,
    search: Searcher,
    fetch: Callable[[str, float], Page],
    directory: Path,
    now: Callable[[], dt.datetime],
    log: Callable[[str], None],
) -> dict[str, object]:
    """Answer one SearchRequest with a SearchResponse; real reasons go to log.

    Raises for a request that does not parse, a session whose turn cannot be
    claimed, or a failed Kagi search: the service answers those with HTTP 503.
    """
    deadline = time.monotonic() + CALL_DEADLINE_SECONDS
    request = parse_request(value)
    session = Session(directory, request.session)
    turn, refs = session.begin()
    call = _Call(turn, refs, fetch, now().date(), log, deadline)
    _housekeep(call, "remove stale sessions", lambda: session.prune(now()))
    if schema_violation(request.commands):
        log("sports without tool 'sports': answered with the service's schema error")
        return _response(SCHEMA_ERROR.format(request.commands) + RUN_SCHEMA, [])
    unknown = _unknown_ref(call, request)
    if unknown is not None:
        log(f"unknown ref_id {unknown!r}: answered with the service's internal error")
        return _response(UNKNOWN_REF, [])
    budget = request.max_output_tokens * CHARS_PER_TOKEN
    operations_left = sum(len(group.operations) for group in request.groups)
    for group in request.groups:
        if group.key == "search_query":
            _search(call, request, search, group)
        elif group.key in PAGE_KINDS:
            for operation in group.operations:
                _view(call, operation, _page_budget(call, budget, operations_left))
                operations_left -= 1
        elif group.key == "time":
            _time(call, group, now())
        else:
            log(f"{group.key}: not served; left out as the service leaves out invalid items")
    _housekeep(call, "save this call's refs", lambda: session.record(call.new_refs))
    output = fit_blocks(call.blocks, budget) if call.blocks else NO_TOOL_RESPONSE
    return _response(output, call.results)


def _response(output: str, results: list[dict[str, object]]) -> dict[str, object]:
    return {"encrypted_output": None, "output": output, "results": results}


def _housekeep(call: _Call, what: str, action: Callable[[], None]) -> None:
    """Run a state chore whose failure must not cost the call its response."""
    try:
        action()
    except Exception as error:  # noqa: BLE001 - the response matters more than the chore
        call.log(f"could not {what}: {' '.join(str(error).split()) or type(error).__name__}")


# The log


def log_path() -> Path:
    """Return the log file that holds the real reasons behind failures."""
    return state_root() / "web-run.log"


def main() -> int:
    """Read a SearchRequest on stdin and print the SearchResponse on stdout.

    A whole-call failure prints only what Codex prints for the service's HTTP 503
    and logs the real reason.
    """
    log = FileLog(log_path())
    try:
        value: object = json.loads(sys.stdin.buffer.read())
        response = handle(
            value,
            search=cli.run,
            fetch=fetch_page,
            directory=state_directory(),
            now=lambda: dt.datetime.now(dt.UTC),
            log=log,
        )
    except Exception as error:  # noqa: BLE001 - every failure answers as the service's 503
        log(f"call failed: {type(error).__name__}: {error}\n{traceback.format_exc()}")
        sys.stderr.write(SERVICE_UNAVAILABLE)
        return FAILURE_EXIT
    sys.stdout.write(json.dumps(response) + "\n")
    return 0
