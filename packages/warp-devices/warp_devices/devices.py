# Copyright (c) 2026 Bad3r
"""Merge registrations, physical devices, and DEX fleet status into one listing."""

import threading
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta
from typing import TYPE_CHECKING, cast

from warp_devices.api import ApiError, Getter, Json, paginate_cursor, paginate_pages
from warp_devices.timefmt import DataError, iso_utc, parse_optional

if TYPE_CHECKING:
    from collections.abc import Callable

CONNECTED = "connected"
OFFLINE = "offline"
UNKNOWN = "unknown"
# longest window DEX accepts
STATUS_WINDOW = timedelta(minutes=60)
REGISTRATIONS = "devices/registrations"
PHYSICAL_DEVICES = "devices/physical-devices"
FLEET_STATUS = "dex/fleet-status/devices"
JOIN_POLL_SECONDS = 0.2


def field(record: Json, *keys: str) -> str | None:
    """Return a nested string field, or None when any level is missing or not a string."""
    *parents, last = keys
    current = record
    for key in parents:
        child = current.get(key)
        if not isinstance(child, dict):
            return None
        current = cast("Json", child)
    value = current.get(last)
    return value if isinstance(value, str) and value else None


@dataclass(frozen=True)
class Device:
    """One active WARP registration and what the other endpoints say about it."""

    name: str
    registration_id: str
    device_id: str | None
    status: str
    status_at: str | None
    colo: str | None
    mesh_ipv4: str | None
    mesh_ipv6: str | None
    public_ip: str | None
    os: str | None
    user: str | None
    last_seen: str | None
    client_version: str | None

    @property
    def last_seen_at(self) -> datetime | None:
        """Return the parsed last-seen time."""
        return parse_optional(self.last_seen)

    def to_json(self) -> Json:
        """Return the record as plain JSON values."""
        return asdict(self)


@dataclass(frozen=True)
class Listing:
    """The merged devices and the endpoints that failed while building them."""

    devices: list[Device]
    warnings: list[str]


@dataclass(frozen=True)
class Reports:
    """The newest DEX report of each registration, and of each device for reports without one."""

    by_registration: dict[str, Json]
    by_device: dict[str, Json]


def latest_reports(fleet: list[Json]) -> Reports:
    """Index the newest DEX report by registration ID, raising DataError on a bad timestamp.

    Only reports without a registration ID fall back to the device ID, so a
    second registration on one device never inherits another's status.
    """
    indexes: dict[str, dict[str, Json]] = {"registration": {}, "device": {}}
    newest: dict[tuple[str, str], datetime] = {}
    for report in fleet:
        moment = parse_optional(report.get("timestamp"))
        if moment is None:
            msg = "a DEX report has no timestamp"
            raise DataError(msg)
        registration_id = field(report, "registrationId")
        kind, key = (
            ("registration", registration_id)
            if registration_id
            else ("device", field(report, "deviceId"))
        )
        if key is None:
            continue
        seen = newest.get((kind, key))
        if seen is None or moment > seen:
            newest[kind, key] = moment
            indexes[kind][key] = report
    return Reports(indexes["registration"], indexes["device"])


def merge(
    registrations: list[Json], physical: list[Json] | None, reports: Reports | None
) -> list[Device]:
    """Join the three endpoints; None marks an endpoint that failed or sent malformed data."""
    hardware = {key: item for item in physical or [] if (key := field(item, "id"))}
    index = reports or Reports({}, {})
    devices: list[Device] = []
    for registration in registrations:
        # reject a malformed last_seen_at
        parse_optional(registration.get("last_seen_at"))
        registration_id = field(registration, "id") or ""
        device_id = field(registration, "device", "id")
        report = index.by_registration.get(registration_id) or (
            index.by_device.get(device_id) if device_id else None
        )
        box = hardware.get(device_id or "", {})
        if reports is None:
            status = UNKNOWN
        elif report is None:
            status = OFFLINE
        else:
            status = field(report, "status") or UNKNOWN
        devices.append(
            Device(
                name=field(registration, "device", "name") or registration_id,
                registration_id=registration_id,
                device_id=device_id,
                status=status,
                status_at=field(report, "timestamp") if report else None,
                colo=field(report, "colo") if report else None,
                mesh_ipv4=field(registration, "virtual_ipv4"),
                mesh_ipv6=field(registration, "virtual_ipv6"),
                public_ip=field(box, "public_ip"),
                os=field(box, "device_type"),
                user=field(registration, "user", "email"),
                last_seen=field(registration, "last_seen_at"),
                client_version=field(registration, "device", "client_version"),
            )
        )
    devices.sort(key=sort_key)
    return devices


def sort_key(device: Device) -> tuple[bool, bool, float, str]:
    """Order connected devices first, then by most recently seen, never-seen last."""
    seen = device.last_seen_at
    return (
        device.status != CONNECTED,
        seen is None,
        -seen.timestamp() if seen else 0.0,
        device.name.casefold(),
    )


class _Job(threading.Thread):
    """Run one fetch as a daemon thread.

    An interrupt or a failed required fetch then never waits for another fetch's retries.
    """

    def __init__(self, fetch: Callable[[], list[Json]]) -> None:
        super().__init__(daemon=True)
        self._fetch = fetch
        self.items: list[Json] | None = None
        self.error: Exception | None = None

    def run(self) -> None:
        try:
            self.items = self._fetch()
        except Exception as error:  # noqa: BLE001 - re-raised in the waiting thread
            self.error = error

    def wait(self) -> list[Json]:
        """Join with a timeout, which keeps the main thread responsive to Ctrl-C."""
        while self.is_alive():
            self.join(JOIN_POLL_SECONDS)
        if self.error is not None:
            raise self.error
        return self.items or []


def load(client: Getter, now: datetime) -> Listing:
    """Fetch the three endpoints concurrently and merge them.

    Registrations are required; the other two degrade to a warning, and so does malformed DEX data.
    """
    window = {
        "source": "last_seen",
        "from": iso_utc(now - STATUS_WINDOW),
        "to": iso_utc(now),
    }
    jobs = {
        REGISTRATIONS: _Job(
            lambda: paginate_cursor(client, REGISTRATIONS, {"registration_type": "warp"})
        ),
        PHYSICAL_DEVICES: _Job(lambda: paginate_cursor(client, PHYSICAL_DEVICES)),
        FLEET_STATUS: _Job(lambda: paginate_pages(client, FLEET_STATUS, window)),
    }
    for job in jobs.values():
        job.start()
    registrations = jobs[REGISTRATIONS].wait()
    warnings: list[str] = []
    optional: dict[str, list[Json] | None] = {}
    for name in (PHYSICAL_DEVICES, FLEET_STATUS):
        try:
            optional[name] = jobs[name].wait()
        except ApiError as error:
            warnings.append(str(error))
            optional[name] = None
    fleet = optional[FLEET_STATUS]
    reports: Reports | None = None
    if fleet is not None:
        try:
            reports = latest_reports(fleet)
        except DataError as error:
            warnings.append(f"GET {FLEET_STATUS} returned malformed data: {error}")
    if optional[PHYSICAL_DEVICES] is None:
        warnings.append("public IP and OS are unknown")
    if reports is None:
        warnings.append("device status is unknown")
    return Listing(merge(registrations, optional[PHYSICAL_DEVICES], reports), warnings)
