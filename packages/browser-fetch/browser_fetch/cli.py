# Copyright (c) 2026 Bad3r
"""Command line of the browser-fetch app."""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import json
import os
import shutil
import signal
import sys
import tempfile
import time
import traceback
from pathlib import Path
from typing import TYPE_CHECKING, Any, NoReturn

from browser_fetch import browser, convert, curl, fetch, tools, urls
from browser_fetch import cookies as jar

if TYPE_CHECKING:
    from types import FrameType

USAGE_EXIT = 2
COOKIE_EXIT = 3
FETCH_EXIT = 4
BROWSER_EXIT = 5
CONVERT_EXIT = 6
INTERNAL_EXIT = 7
WORK_PREFIX = "browser-fetch-"
# Held by the run that owns a work directory, for as long as it runs.
OWNER = ".owner"
# A directory this old without an owner file was left between mkdtemp and the lock.
ORPHAN_SECONDS = 60


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="browser-fetch",
        description=(
            "Fetch a web page with curl-impersonate and LibreWolf's cookies, falling back "
            "to Camoufox on a private display for challenges and script-built pages."
        ),
        epilog=(
            f"Exit status: {USAGE_EXIT} invalid URL, {COOKIE_EXIT} LibreWolf's cookies "
            f"unreadable, {FETCH_EXIT} fetch failed, {BROWSER_EXIT} browser failed, "
            f"{CONVERT_EXIT} document conversion failed, {INTERNAL_EXIT} unexpected error. A host "
            "that resolves to this machine or a private network is refused with "
            f"{FETCH_EXIT}."
        ),
    )
    parser.add_argument("url")
    parser.add_argument("--json", action="store_true", help="print the WebFetch record as JSON")
    parser.add_argument(
        "--offset", type=int, default=0, help="first UTF-16 code unit of the text to print"
    )
    parser.add_argument(
        "--max-chars", type=int, default=None, help="print at most this many code units"
    )
    parser.add_argument(
        "--browser",
        choices=["auto", "never", "always"],
        default="auto",
        help="when to render in Camoufox",
    )
    parser.add_argument("--no-cookies", action="store_true", help="send no LibreWolf cookies")
    parser.add_argument(
        "--deadline", type=float, default=240.0, help="seconds the whole fetch may take"
    )
    return parser


def _runtime_base() -> Path:
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    return Path(runtime) if runtime and Path(runtime).is_dir() else Path(tempfile.gettempdir())


def _save_dir() -> Path:
    cache = os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    return Path(cache) / "browser-fetch"


def _state_dir() -> Path:
    state = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local" / "state")
    return Path(state) / "browser-fetch"


def sweep(base: Path) -> None:
    """Remove work directories whose run is gone, as after a SIGKILL.

    A run holds an flock on its directory's owner file while it lives, so the
    test works across PID namespaces; anything that vanishes or cannot be
    read meanwhile is another run's business and is left alone.
    """
    try:
        entries = list(base.glob(f"{WORK_PREFIX}*"))
    except OSError:
        return
    for entry in entries:
        try:
            if entry.stat().st_uid != os.getuid():
                continue
            fd = os.open(entry / OWNER, os.O_RDWR | os.O_CLOEXEC)
        except FileNotFoundError:
            with contextlib.suppress(OSError):
                if time.time() - entry.stat().st_mtime > ORPHAN_SECONDS:
                    shutil.rmtree(entry, ignore_errors=True)
            continue
        except OSError:
            continue
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            continue
        else:
            shutil.rmtree(entry, ignore_errors=True)
        finally:
            os.close(fd)


def claim(workdir: Path) -> int:
    """Create and lock the work directory's owner file; the lock lasts the run.

    The file is locked before it takes its name, so a sweep never finds it
    unlocked; until then the directory is too young to count as orphaned.
    """
    partial = workdir / f"{OWNER}.partial"
    fd = os.open(partial, os.O_RDWR | os.O_CREAT | os.O_CLOEXEC, 0o600)
    fcntl.flock(fd, fcntl.LOCK_EX)
    partial.rename(workdir / OWNER)
    return fd


def _terminate(signum: int, frame: FrameType | None) -> NoReturn:  # noqa: ARG001
    raise SystemExit(128 + signum)


def camoufox(workdir: Path) -> browser.Camoufox:
    """The fallback browser with its state under XDG_STATE_HOME."""
    return browser.Camoufox(
        browser.Tools(tools.UNSHARE, tools.SESSION, tools.CAMOUFOX_VERSION, tools.PASTA),
        _state_dir(),
        workdir,
    )


def record(page: fetch.Page, offset: int, max_chars: int | None) -> dict[str, Any]:
    """Return the page as the JSON record the plugin reads."""
    stop = None if max_chars is None else offset + max(max_chars, 0)
    out: dict[str, Any] = {
        "outcome": page.outcome,
        "url": page.url,
        "status": page.status,
        "statusText": page.status_text,
        "contentType": page.content_type,
        "bytes": page.bytes,
        # Raw bytes only: converted text pages like any other.
        "binary": convert.is_binary(page.content_type) and not page.converted,
        "preapproved": urls.is_preapproved(page.url),
        "length": convert.utf16_length(page.text),
        "offset": offset,
        "text": convert.utf16_slice(page.text, offset, stop) if offset >= 0 else "",
        "via": page.via,
    }
    optional = {
        "reason": page.reason,
        "redirectFrom": page.redirect_from,
        "redirectTo": page.redirect_to,
        "retryAfter": page.retry_after,
        "savedPath": page.saved_path,
        "savedBytes": page.saved_bytes,
    }
    out.update({key: value for key, value in optional.items() if value is not None})
    return out


def _render_text(page: fetch.Page) -> str:
    if page.outcome == "redirect":
        return f"{page.url} redirects ({page.status}) to {page.redirect_to}"
    if page.outcome == "http_error":
        return f"{page.url} answered HTTP {page.status} {page.status_text}"
    return page.text


def _fail(message: str, code: int) -> int:
    print(f"browser-fetch: {message}", file=sys.stderr)
    return code


def _unexpected(error: BaseException) -> int:
    """One line for the plugin; the stack, without messages, only on request."""
    if os.environ.get("BROWSER_FETCH_DEBUG"):
        print("".join(traceback.format_tb(error.__traceback__)), file=sys.stderr)
    return _fail(f"unexpected {type(error).__name__}", INTERNAL_EXIT)


def main(argv: list[str] | None = None) -> int:  # noqa: PLR0911 - one exit per failure class
    """Run the command line and return its exit status."""
    os.umask(0o077)
    args = _parser().parse_args(argv)
    for signum in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        signal.signal(signum, _terminate)
    base = _runtime_base()
    sweep(base)
    workdir = Path(tempfile.mkdtemp(prefix=f"{WORK_PREFIX}{os.getpid()}-", dir=base))
    owner = claim(workdir)
    try:
        settings = fetch.Settings(
            curl=tools.CURL,
            browser=camoufox(workdir),
            workdir=workdir,
            save_dir=_save_dir(),
            use_cookies=not args.no_cookies,
            browser_mode=args.browser,
            deadline=args.deadline,
            resolve=urls.lookup,
        )
        page = fetch.fetch(args.url, settings)
    except urls.UrlError as error:
        return _fail(str(error), USAGE_EXIT)
    except jar.CookieError as error:
        return _fail(str(error), COOKIE_EXIT)
    except (fetch.FetchError, curl.TransportError, urls.AddressError) as error:
        return _fail(str(error), FETCH_EXIT)
    except browser.BrowserError as error:
        return _fail(str(error), BROWSER_EXIT)
    except convert.ConversionError as error:
        return _fail(str(error), CONVERT_EXIT)
    except Exception as error:  # noqa: BLE001 - anything else is one line, not a traceback
        return _unexpected(error)
    finally:
        with contextlib.suppress(FileNotFoundError):
            shutil.rmtree(workdir)
        os.close(owner)
    _print(page, args)
    return 0


def _print(page: fetch.Page, args: argparse.Namespace) -> None:
    if os.environ.get("BROWSER_FETCH_DEBUG"):
        for note in page.notes:
            print(f"browser-fetch: note: {note}", file=sys.stderr)
    if args.json:
        print(json.dumps(record(page, max(args.offset, 0), args.max_chars)))
    else:
        print(_render_text(page))
