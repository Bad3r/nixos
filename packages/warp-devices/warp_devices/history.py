# Copyright (c) 2026 Bad3r
"""Per-device DEX report history and its change filter."""

from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import TYPE_CHECKING

from warp_devices.api import Json, paginate_cursor, paginate_pages
from warp_devices.devices import FLEET_STATUS, PHYSICAL_DEVICES, field
from warp_devices.timefmt import iso_utc, parse

if TYPE_CHECKING:
    from warp_devices.api import Getter

MIN_HOURS = 1
# DEX keeps raw reports for seven days.
MAX_HOURS = 168
DEFAULT_HOURS = 24
# An awake client reports every two minutes and a sleeping one every twenty.
GAP_SECONDS = 300


class LookupFailedError(Exception):
    """No device, or more than one, matches the query."""


@dataclass(frozen=True)
class Report:
    """One DEX fleet-status report, reduced to the fields history shows."""

    timestamp: str
    moment: datetime
    status: str | None
    colo: str | None
    isp_ipv4: str | None
    lan_ipv4: str | None
    gateway_ipv4: str | None
    handshake_ms: float | None
    loss_pct: float | None

    def signature(self) -> tuple[str | None, ...]:
        """Return the fields whose change makes a report worth showing."""
        return (self.status, self.colo, self.isp_ipv4, self.lan_ipv4, self.gateway_ipv4)


@dataclass(frozen=True)
class Entry:
    """A report and the gap since the one before it."""

    report: Report
    gap_seconds: float | None

    def to_json(self) -> Json:
        """Return the entry as plain JSON values."""
        r = self.report
        return {
            "timestamp": r.timestamp,
            "status": r.status,
            "colo": r.colo,
            "isp_ipv4": r.isp_ipv4,
            "lan_ipv4": r.lan_ipv4,
            "gateway_ipv4": r.gateway_ipv4,
            "handshake_ms": r.handshake_ms,
            "loss_pct": r.loss_pct,
            "gap_seconds": self.gap_seconds,
        }


def _number(record: Json, key: str) -> float | None:
    value = record.get(key)
    if isinstance(value, bool) or not isinstance(value, int | float):
        return None
    return float(value)


def to_report(record: Json) -> Report:
    """Reduce one raw DEX record."""
    timestamp = field(record, "timestamp")
    if timestamp is None:
        msg = "a DEX report has no timestamp"
        raise ValueError(msg)
    return Report(
        timestamp=timestamp,
        moment=parse(timestamp),
        status=field(record, "status"),
        colo=field(record, "colo"),
        isp_ipv4=field(record, "ispIpv4", "address"),
        lan_ipv4=field(record, "deviceIpv4", "address"),
        gateway_ipv4=field(record, "gatewayIpv4", "address"),
        handshake_ms=_number(record, "handshakeLatencyMs"),
        loss_pct=_number(record, "estimatedLossPct"),
    )


def resolve(physical: list[Json], query: str) -> Json:
    """Find one device by exact ID or case-insensitive name."""
    by_id = [device for device in physical if field(device, "id") == query]
    if by_id:
        return by_id[0]
    wanted = query.casefold()
    by_name = [device for device in physical if (field(device, "name") or "").casefold() == wanted]
    if not by_name:
        msg = f"no device named {query!r}"
        raise LookupFailedError(msg)
    if len(by_name) > 1:
        ids = ", ".join(field(device, "id") or "?" for device in by_name)
        msg = f"{len(by_name)} devices are named {query!r}; pass one ID: {ids}"
        raise LookupFailedError(msg)
    return by_name[0]


def entries(reports: list[Report], *, show_all: bool) -> list[Entry]:
    """Sort reports and keep the first, the last, changes, and gaps over GAP_SECONDS."""
    ordered = sorted(reports, key=lambda report: report.moment)
    kept: list[Entry] = []
    for index, report in enumerate(ordered):
        previous = ordered[index - 1] if index else None
        gap = (report.moment - previous.moment).total_seconds() if previous else None
        if (
            show_all
            or previous is None
            or index == len(ordered) - 1
            or report.signature() != previous.signature()
            or (gap is not None and gap > GAP_SECONDS)
        ):
            kept.append(Entry(report, gap))
    return kept


def load(client: Getter, query: str, hours: int, now: datetime) -> tuple[Json, list[Report]]:
    """Resolve the device and fetch its raw reports over the past hours."""
    device = resolve(paginate_cursor(client, PHYSICAL_DEVICES), query)
    device_id = field(device, "id") or ""
    window = {
        "source": "raw",
        "device_id": device_id,
        "from": iso_utc(now - timedelta(hours=hours)),
        "to": iso_utc(now),
        "sort_by": "timestamp",
    }
    records = paginate_pages(client, FLEET_STATUS, window)
    return device, [to_report(record) for record in records]
