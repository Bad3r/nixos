# Copyright (c) 2026 Bad3r
"""Fake API answers built from documentation addresses only."""

import json
import os
import time
from datetime import UTC, datetime, timedelta
from typing import TYPE_CHECKING, cast

from warp_devices.api import Json, Response

if TYPE_CHECKING:
    from collections.abc import Callable, Mapping

NOW = datetime(2026, 11, 3, 3, 30, tzinfo=UTC)
TOKEN = "test-token-0123456789"  # noqa: S105 - a fixture value, never a credential


def pin_utc() -> None:
    """Render local times in UTC so assertions do not depend on the host zone."""
    os.environ["TZ"] = "UTC"
    time.tzset()


def stamp(minutes_ago: float) -> str:
    """Return an RFC 3339 time the given minutes before NOW."""
    return (NOW - timedelta(minutes=minutes_ago)).strftime("%Y-%m-%dT%H:%M:%S.123456Z")


def dex_stamp(minutes_ago: float) -> str:
    """Return a DEX-style time the given minutes before NOW."""
    return (NOW - timedelta(minutes=minutes_ago)).strftime("%Y-%m-%d %H:%M:%S.5+00")


def registration(
    name: str, number: int, *, minutes_ago: float | None, ipv6: bool = True, user: str | None = None
) -> Json:
    """Return one registration record."""
    record: Json = {
        "id": f"reg-{number}",
        "device": {"id": f"dev-{number}", "name": name, "client_version": "2026.8.2115"},
        "virtual_ipv4": f"100.96.0.{number}",
    }
    if ipv6:
        record["virtual_ipv6"] = f"2001:db8::{number}"
    if user:
        record["user"] = {"email": user}
    if minutes_ago is not None:
        record["last_seen_at"] = stamp(minutes_ago)
    return record


def hardware(number: int, *, name: str, os_name: str = "linux") -> Json:
    """Return one physical-device record."""
    return {
        "id": f"dev-{number}",
        "name": name,
        "public_ip": f"203.0.113.{number}",
        "device_type": os_name,
    }


def report(number: int, status: str, minutes_ago: float, *, registration_id: bool = True) -> Json:
    """Return one DEX fleet-status record."""
    record: Json = {
        "deviceId": f"dev-{number}",
        "status": status,
        "timestamp": dex_stamp(minutes_ago),
        "colo": "JED",
    }
    if registration_id:
        record["registrationId"] = f"reg-{number}"
    return record


def envelope(result: list[Json], **info: object) -> Json:
    """Return a successful Cloudflare envelope."""
    return {"success": True, "errors": [], "result": result, "result_info": info}


type Handler = Callable[[Mapping[str, str]], Json]


class FakeGetter:
    """Answer GETs from per-path handlers and record each call."""

    def __init__(self, routes: dict[str, Handler]) -> None:
        """Keep the routes."""
        self.routes = routes
        self.calls: list[tuple[str, dict[str, str]]] = []

    def get(self, path: str, params: Mapping[str, str]) -> Json:
        """Dispatch to the handler of the path."""
        self.calls.append((path, dict(params)))
        return self.routes[path](params)


def static(result: list[Json]) -> Handler:
    """Return a handler that answers one page."""
    return lambda _params: envelope(result)


class FakeTransport:
    """Play back answers or exceptions in order and record the requests."""

    def __init__(self, *answers: Response | Exception) -> None:
        """Keep the queue."""
        self.answers = list(answers)
        self.requests: list[tuple[str, dict[str, str], float]] = []

    def __call__(self, url: str, headers: Mapping[str, str], timeout: float) -> Response:
        """Return or raise the next queued answer."""
        self.requests.append((url, dict(headers), timeout))
        answer = self.answers.pop(0)
        if isinstance(answer, Exception):
            raise answer
        return answer


def ok(body: object, status: int = 200) -> Response:
    """Return an answer with a JSON body."""
    return Response(status, json.dumps(body).encode())


def as_json(value: object) -> Json:
    """Narrow a decoded JSON value for the type checker."""
    return cast("Json", value)
