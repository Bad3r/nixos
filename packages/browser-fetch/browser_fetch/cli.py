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
from urllib.parse import urlsplit

from browser_fetch import browser, convert, curl, display, fetch, tools, urls
from browser_fetch import cookies as jar

if TYPE_CHECKING:
    from collections.abc import Generator
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
LOGIN = "login"
LOGIN_URL = "https://kagi.com/signin"


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="browser-fetch",
        description=(
            "Fetch a web page with curl-impersonate and Camoufox's cookie jar, falling back "
            "to Camoufox on a private display for challenges and script-built pages."
        ),
        epilog=(
            f"Exit status: {USAGE_EXIT} invalid URL, {COOKIE_EXIT} Camoufox's cookie database "
            f"unusable, {FETCH_EXIT} fetch failed, {BROWSER_EXIT} browser failed, "
            f"{CONVERT_EXIT} document conversion failed, {INTERNAL_EXIT} unexpected error. A host "
            "that resolves to this machine or a private network is refused with "
            f"{FETCH_EXIT}. Run 'browser-fetch {LOGIN} [URL]' to sign in to a site in Camoufox."
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
    parser.add_argument(
        "--no-cookies",
        action="store_true",
        help="neither read nor write Camoufox's cookie jar; the browser gets a throwaway profile",
    )
    parser.add_argument(
        "--deadline", type=float, default=240.0, help="seconds the whole fetch may take"
    )
    return parser


def _runtime_base() -> Path:
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    return Path(runtime) if runtime and Path(runtime).is_dir() else Path(tempfile.gettempdir())


def save_dir() -> Path:
    """Where binary bodies are saved, under XDG_CACHE_HOME."""
    cache = os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    return Path(cache) / "browser-fetch"


def state_dir() -> Path:
    """Camoufox's profile and fingerprint, under XDG_STATE_HOME."""
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


def _login_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog=f"browser-fetch {LOGIN}",
        description=(
            "Open a page in a Camoufox window on this display, with the profile and fingerprint "
            "fetches use, to sign in by hand; closing the window saves the cookies to the jar."
        ),
        epilog=(
            f"Exit status: {USAGE_EXIT} not an http or https URL, {COOKIE_EXIT} Camoufox's "
            f"cookie database unusable, {BROWSER_EXIT} browser failed, {INTERNAL_EXIT} unexpected "
            "error."
        ),
    )
    parser.add_argument("url", nargs="?", default=LOGIN_URL, help=f"default {LOGIN_URL}")
    return parser


def _terminate(signum: int, frame: FrameType | None) -> NoReturn:  # noqa: ARG001
    raise SystemExit(128 + signum)


def exit_on_signals() -> None:
    """Turn SIGTERM, SIGHUP and SIGINT into SystemExit, so cleanup runs on the way out."""
    for signum in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        signal.signal(signum, _terminate)


@contextlib.contextmanager
def workspace() -> Generator[Path]:
    """A private work directory for one run, removed with it; one a killed run left is swept."""
    base = _runtime_base()
    sweep(base)
    workdir = Path(tempfile.mkdtemp(prefix=f"{WORK_PREFIX}{os.getpid()}-", dir=base))
    owner = claim(workdir)
    try:
        yield workdir
    finally:
        with contextlib.suppress(FileNotFoundError):
            shutil.rmtree(workdir)
        os.close(owner)


def camoufox(workdir: Path) -> browser.Camoufox:
    """The fallback browser with its state under XDG_STATE_HOME."""
    return browser.Camoufox(
        browser.Tools(tools.UNSHARE, tools.SESSION, tools.CAMOUFOX_VERSION, tools.PASTA),
        state_dir(),
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
        "length": convert.utf16_length(page.text),
        "offset": offset,
        "text": convert.utf16_slice(page.text, offset, stop),
        "via": page.via,
    }
    if page.warnings:
        out["warnings"] = page.warnings
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


def _warn(warnings: list[str]) -> None:
    for warning in warnings:
        print(f"browser-fetch: warning: {warning}", file=sys.stderr)


def _fail(message: str, code: int, error: BaseException | None = None) -> int:
    """Print the error's warnings, then its message on the last line."""
    _warn(list(getattr(error, "__notes__", [])))
    print(f"browser-fetch: {message}", file=sys.stderr)
    return code


def _unexpected(error: BaseException) -> int:
    """One line for the plugin; the stack, without messages, only on request."""
    if os.environ.get("BROWSER_FETCH_DEBUG"):
        print("".join(traceback.format_tb(error.__traceback__)), file=sys.stderr)
    return _fail(f"unexpected {type(error).__name__}", INTERNAL_EXIT, error)


def main(argv: list[str] | None = None) -> int:  # noqa: PLR0911 - one exit per failure class
    """Run the command line and return its exit status."""
    os.umask(0o077)
    given = sys.argv[1:] if argv is None else argv
    if given[:1] == [LOGIN]:
        return login(given[1:])
    args = _parser().parse_args(given)
    exit_on_signals()
    try:
        with workspace() as workdir:
            settings = fetch.Settings(
                curl=tools.CURL,
                browser=camoufox(workdir),
                workdir=workdir,
                save_dir=save_dir(),
                use_cookies=not args.no_cookies,
                browser_mode=args.browser,
                deadline=args.deadline,
                resolve=urls.lookup,
            )
            page = fetch.fetch(args.url, settings)
    except urls.UrlError as error:
        return _fail(str(error), USAGE_EXIT, error)
    except jar.CookieError as error:
        return _fail(str(error), COOKIE_EXIT, error)
    except (fetch.FetchError, curl.TransportError, urls.AddressError) as error:
        return _fail(str(error), FETCH_EXIT, error)
    except browser.BrowserError as error:
        return _fail(str(error), BROWSER_EXIT, error)
    except convert.ConversionError as error:
        return _fail(str(error), CONVERT_EXIT, error)
    except Exception as error:  # noqa: BLE001 - anything else is one line, not a traceback
        return _unexpected(error)
    except SystemExit as error:
        # A signal: the exit status says so, and the warnings still go out.
        _warn(list(getattr(error, "__notes__", [])))
        raise
    _print(page, args)
    return 0


def login(argv: list[str]) -> int:
    """Run browser-fetch login: a window on the user's display until they close it."""
    args = _login_parser().parse_args(argv)
    exit_on_signals()
    url = str(args.url)
    try:
        host = urlsplit(url).hostname if urlsplit(url).scheme in {"http", "https"} else None
    except ValueError:
        host = None
    if not host:
        return _fail(f"not an http or https URL: {url}", USAGE_EXIT)
    try:
        screen = display.local_display(os.environ)
        with workspace() as workdir:
            fallback = camoufox(workdir)
            print(f"browser-fetch: opening {url}; close the window when done", file=sys.stderr)
            warnings = fallback.login(url, screen, time.monotonic() + browser.LOGIN_SECONDS)
            database = fallback.profile / jar.DB_NAME
            try:
                stored = fallback.jar(time.monotonic() + browser.JAR_LOCK_SECONDS + 1)
            except browser.BrowserError as error:
                warnings.append(f"the jar could not be read back: {error}")
                stored = None
    except jar.CookieError as error:
        return _fail(str(error), COOKIE_EXIT, error)
    except (browser.BrowserError, display.DisplayError) as error:
        return _fail(str(error), BROWSER_EXIT, error)
    except Exception as error:  # noqa: BLE001 - anything else is one line, not a traceback
        return _unexpected(error)
    _warn(warnings)
    if stored is not None:
        kept = jar.for_request(stored, url, jar.now_us() // 1000)
        print(f"{len(kept)} cookies for {host} are in {database}")
    return 0


def _print(page: fetch.Page, args: argparse.Namespace) -> None:
    _warn(page.warnings)
    if os.environ.get("BROWSER_FETCH_DEBUG"):
        for note in page.notes:
            print(f"browser-fetch: note: {note}", file=sys.stderr)
    if args.json:
        print(json.dumps(record(page, max(args.offset, 0), args.max_chars)))
    else:
        print(_render_text(page))
