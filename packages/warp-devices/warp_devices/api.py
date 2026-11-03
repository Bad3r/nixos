# Copyright (c) 2026 Bad3r
"""Cloudflare API client that retries the stalling Zero Trust device endpoints."""

import http.client
import json
import math
import random
import ssl
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import TYPE_CHECKING, Protocol, cast

if TYPE_CHECKING:
    from collections.abc import Callable, Mapping

API_ROOT = "https://api.cloudflare.com/client/v4"
TIMEOUT_SECONDS = 20.0
ATTEMPTS = 5
BACKOFF_CAP_SECONDS = 8.0
RETRY_AFTER_CAP_SECONDS = 30.0
MAX_PAGES = 1000
CURSOR_PAGE_SIZE = 100
NUMBERED_PAGE_SIZE = 50
HTTP_OK = 200
SERVER_ERROR = 500
RETRY_STATUSES = frozenset({408, 429})

type Json = dict[str, object]


@dataclass(frozen=True)
class Response:
    """One HTTP answer: status, raw body, and the Retry-After header if any."""

    status: int
    body: bytes
    retry_after: str | None = None


# send one GET
type Transport = Callable[[str, Mapping[str, str], float], Response]


class ApiError(Exception):
    """A request that failed for good, after any retries."""

    def __init__(self, endpoint: str, message: str, *, status: int | None = None) -> None:
        """Name the endpoint, never the URL with its query or the headers."""
        super().__init__(f"GET {endpoint} failed: {message}")
        self.endpoint = endpoint
        self.status = status


class Getter(Protocol):
    """Anything that answers a GET on an account path with a decoded envelope."""

    def get(self, path: str, params: Mapping[str, str]) -> Json:
        """Return the decoded response envelope of one successful GET."""
        ...


def urllib_transport(url: str, headers: Mapping[str, str], timeout: float) -> Response:
    """Send one GET through urllib."""
    request = urllib.request.Request(url, headers=dict(headers))  # noqa: S310 - API_ROOT is https
    try:
        with urllib.request.urlopen(request, timeout=timeout) as answer:  # noqa: S310
            return Response(answer.status, answer.read(), answer.headers.get("Retry-After"))
    except urllib.error.HTTPError as error:
        with error:
            retry_after = error.headers.get("Retry-After")
            try:
                body = error.read()
            except OSError, http.client.HTTPException:
                body = b""
            return Response(error.code, body, retry_after)


def cloudflare_messages(body: object) -> str:
    """Join the messages of a Cloudflare error envelope."""
    if not isinstance(body, dict):
        return ""
    errors = cast("dict[str, object]", body).get("errors")
    if not isinstance(errors, list):
        return ""
    messages: list[str] = []
    for entry in cast("list[object]", errors):
        if isinstance(entry, dict):
            message = cast("dict[str, object]", entry).get("message")
            if isinstance(message, str) and message:
                messages.append(message)
    return "; ".join(messages)


def _retry_after(value: str | None) -> float | None:
    if value is None:
        return None
    try:
        seconds = float(value)
    except ValueError:
        return None
    if not math.isfinite(seconds):
        return None
    return min(max(seconds, 0.0), RETRY_AFTER_CAP_SECONDS)


def _certificate_failure(error: Exception) -> ssl.SSLCertVerificationError | None:
    """Return the certificate error behind a failed request, bare or wrapped by urllib."""
    reason = error.reason if isinstance(error, urllib.error.URLError) else error
    return reason if isinstance(reason, ssl.SSLCertVerificationError) else None


def _is_object_list(value: object) -> bool:
    return isinstance(value, list) and all(
        isinstance(item, dict) for item in cast("list[object]", value)
    )


class Client:
    """GETs on one account's list endpoints, retrying stalls, bad bodies, 408, 429, and 5xx."""

    def __init__(
        self,
        account_id: str,
        token: str,
        *,
        transport: Transport = urllib_transport,
        sleep: Callable[[float], None] = time.sleep,
        jitter: Callable[[], float] = random.random,
    ) -> None:
        """Keep the token only in the request headers."""
        self._base = f"{API_ROOT}/accounts/{urllib.parse.quote(account_id, safe='')}"
        self._headers = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "User-Agent": "warp-devices",
        }
        self._transport = transport
        self._sleep = sleep
        self._jitter = jitter

    def __repr__(self) -> str:
        """Keep the token out of tracebacks and logs."""
        return "Client(<redacted>)"

    def _backoff(self, attempt: int) -> float:
        return min(BACKOFF_CAP_SECONDS, float(2**attempt)) + self._jitter()

    def get(self, path: str, params: Mapping[str, str]) -> Json:
        """Return the envelope of one GET, or raise ApiError once the attempts run out.

        A 5xx is retried whatever its body says, since the server owns the fault; any other
        status with success false is final.
        """
        url = f"{self._base}/{path}"
        if params:
            url += "?" + urllib.parse.urlencode(params)
        reason = ""
        for attempt in range(ATTEMPTS):
            delay = self._backoff(attempt)
            try:
                response = self._transport(url, self._headers, TIMEOUT_SECONDS)
            except (OSError, http.client.HTTPException) as error:
                if (failure := _certificate_failure(error)) is not None:
                    detail = getattr(failure, "verify_message", None) or failure.strerror
                    msg = f"TLS certificate verification failed: {detail or failure}"
                    raise ApiError(path, msg) from None
                reason = f"{type(error).__name__}: {error}".rstrip(": ")
            except ValueError:
                # keep the token out of the error
                msg = "the request could not be built (invalid header or URL)"
                raise ApiError(path, msg) from None
            else:
                if response.status in RETRY_STATUSES or response.status >= SERVER_ERROR:
                    reason = f"HTTP {response.status}"
                    wait = _retry_after(response.retry_after)
                    delay = delay if wait is None else wait
                else:
                    body = self._decode(path, response)
                    if body is not None:
                        return body
                    reason = "cut-off or malformed body"
            if attempt + 1 < ATTEMPTS:
                self._sleep(delay)
        raise ApiError(path, f"{reason} after {ATTEMPTS} attempts")

    @staticmethod
    def _decode(path: str, response: Response) -> Json | None:
        """Return the envelope, None for a retryable bad 200 body, or raise for an error answer."""
        ok = response.status == HTTP_OK
        try:
            body: object = json.loads(response.body)
        except ValueError:
            if ok:
                return None
            msg = f"HTTP {response.status} with a non-JSON body"
            raise ApiError(path, msg, status=response.status) from None
        envelope = cast("Json", body) if isinstance(body, dict) else None
        success = envelope.get("success") if envelope is not None else None
        listed = envelope is not None and _is_object_list(envelope.get("result"))
        if ok and (not isinstance(success, bool) or (success and not listed)):
            return None
        if envelope is None or success is not True:
            message = cloudflare_messages(envelope) or f"HTTP {response.status}"
            raise ApiError(path, message, status=response.status)
        if not listed:
            msg = f"HTTP {response.status} without a result list"
            raise ApiError(path, msg, status=response.status)
        return envelope


def results(envelope: Json) -> list[Json]:
    """Return the result list Client.get already checked."""
    return cast("list[Json]", envelope["result"])


def _info(envelope: Json) -> Json:
    info = envelope.get("result_info")
    return cast("Json", info) if isinstance(info, dict) else {}


def paginate_cursor(
    client: Getter, path: str, params: Mapping[str, str] | None = None
) -> list[Json]:
    """Collect every page of a cursor-paginated endpoint."""
    items: list[Json] = []
    cursor: str | None = None
    requested: set[str] = set()
    for _ in range(MAX_PAGES):
        query = {**(params or {}), "per_page": str(CURSOR_PAGE_SIZE)}
        if cursor:
            query["cursor"] = cursor
            requested.add(cursor)
        envelope = client.get(path, query)
        page = results(envelope)
        following = _info(envelope).get("cursor")
        items.extend(page)
        if not page or not isinstance(following, str) or not following:
            return items
        if following in requested:
            msg = "the cursor stopped advancing or looped, so the listing would be incomplete"
            raise ApiError(path, msg)
        cursor = following
    raise ApiError(path, f"more than {MAX_PAGES} pages")


def paginate_pages(
    client: Getter, path: str, params: Mapping[str, str] | None = None
) -> list[Json]:
    """Collect every page of a page-numbered endpoint."""
    items: list[Json] = []
    for number in range(1, MAX_PAGES + 1):
        query = {**(params or {}), "per_page": str(NUMBERED_PAGE_SIZE), "page": str(number)}
        envelope = client.get(path, query)
        page = results(envelope)
        items.extend(page)
        total = _info(envelope).get("total_pages")
        if isinstance(total, bool) or not isinstance(total, int):
            if len(page) < NUMBERED_PAGE_SIZE:
                return items
            msg = "a full page came without total_pages, so the listing may be incomplete"
            raise ApiError(path, msg)
        if not page or number >= total:
            return items
    raise ApiError(path, f"more than {MAX_PAGES} pages")
