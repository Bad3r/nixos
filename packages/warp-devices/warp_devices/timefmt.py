# Copyright (c) 2026 Bad3r
"""Timestamp parsing and human-readable ages."""

import re
from datetime import UTC, datetime

MINUTE = 60
HOUR = 3600
DAY = 86400
_HOUR_ONLY_OFFSET = re.compile(r"[+-]\d{2}$")


class DataError(ValueError):
    """An API response holds a field the CLI cannot read."""


def parse(value: str) -> datetime:
    """Parse an RFC 3339 timestamp or DEX's `2026-11-03 01:24:45.841255+00` form."""
    text = value.strip().replace(" ", "T", 1)
    if text.endswith(("Z", "z")):
        text = text[:-1] + "+00:00"
    elif _HOUR_ONLY_OFFSET.search(text):
        text += ":00"
    try:
        moment = datetime.fromisoformat(text)
    except ValueError:
        msg = f"unrecognized timestamp {value!r}"
        raise DataError(msg) from None
    return moment if moment.tzinfo else moment.replace(tzinfo=UTC)


def parse_optional(value: object) -> datetime | None:
    """Parse a timestamp field that may be absent or empty."""
    if value is None or value == "":
        return None
    if not isinstance(value, str):
        msg = f"unrecognized timestamp {value!r}"
        raise DataError(msg)
    return parse(value)


def _count(number: int, unit: str) -> str:
    return f"{number} {unit}{'' if number == 1 else 's'}"


def ago(moment: datetime, now: datetime) -> str:
    """Say how long ago a moment was; past a day, give the local date and time too.

    The date carries the year when the moment falls in another local year than now.
    """
    seconds = (now - moment).total_seconds()
    if seconds < MINUTE:
        return "just now"
    if seconds < HOUR:
        return f"{_count(int(seconds // MINUTE), 'min')} ago"
    if seconds < DAY:
        return f"{_count(int(seconds // HOUR), 'hour')} ago"
    local = moment.astimezone()
    year = "" if local.year == now.astimezone().year else f" {local.year}"
    days = _count(int(seconds // DAY), "day")
    return f"{local:%a %b} {local.day}{year}, {local:%H:%M} ({days} ago)"


def span(seconds: float) -> str:
    """Format a duration compactly: 45s, 12m, 6h 0m, 2d 3h."""
    whole = int(seconds)
    if whole < MINUTE:
        return f"{whole}s"
    if whole < HOUR:
        return f"{whole // MINUTE}m"
    if whole < DAY:
        return f"{whole // HOUR}h {whole % HOUR // MINUTE}m"
    return f"{whole // DAY}d {whole % DAY // HOUR}h"


def local_clock(moment: datetime) -> str:
    """Format a moment as local weekday, date, and time to the second."""
    local = moment.astimezone()
    return f"{local:%a %b} {local.day:>2} {local:%H:%M:%S}"


def iso_utc(moment: datetime) -> str:
    """Format a moment for an API query."""
    return moment.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
