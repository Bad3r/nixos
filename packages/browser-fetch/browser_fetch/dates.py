# Copyright (c) 2026 Bad3r
"""Cookie dates as Gecko reads them: NSPR's PR_ParseTimeString with default_to_gmt.

CookieParser::GetExpiry parses both Expires and the Date header with it.
It is far more lenient than RFC 6265 section 5.1.1: it takes numeric dates
(06/21/95), AM and PM, zone names and offsets, and out-of-range fields,
which it carries over (Feb 30 is Mar 2). References are to
nsprpub/pr/src/misc/prtime.c of NSPR 4.40, which Firefox 158.0.1 bundles.
"""

from __future__ import annotations

# Zone names, with their offset from GMT and their daylight saving time, in minutes.
_ZONES = {
    b"pst": (-8 * 60, 0),
    b"pdt": (-8 * 60, 60),
    b"mst": (-7 * 60, 0),
    b"mdt": (-7 * 60, 60),
    b"cst": (-6 * 60, 0),
    b"cdt": (-6 * 60, 60),
    b"est": (-5 * 60, 0),
    b"edt": (-5 * 60, 60),
    b"ast": (-4 * 60, 0),
    b"nst": (-3 * 60 - 30, 0),
    b"gmt": (0, 0),
    b"bst": (0, 60),
    b"met": (1 * 60, 0),
    b"eet": (2 * 60, 0),
    b"jst": (9 * 60, 0),
}
_MONTHS = {
    name: index
    for index, name in enumerate((
        b"jan", b"feb", b"mar", b"apr", b"may", b"jun",
        b"jul", b"aug", b"sep", b"oct", b"nov", b"dec",
    ))
}  # fmt: skip
# Where a token ends, and what is skipped between tokens.
_TOKEN_END = frozenset(b" \t,;-+/()[]")
_BETWEEN = frozenset(b" \t,;/()[]")
_LETTERS = frozenset(b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
_MAX_ITERATIONS = 1000
_INT16_MAX = 32767
# lastDayOfMonth and nDays: a common year, then a leap year.
_LAST_DAY = (
    (-1, 30, 58, 89, 119, 150, 180, 211, 242, 272, 303, 333, 364),
    (-1, 30, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365),
)
_DAYS = (
    (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31),
    (31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31),
)
_SECONDS_PER_DAY = 86_400
# PR_ParseTimeString's "no offset yet", which an offset of -0001 also reads as.
_UNSET = -1


def _div(a: int, b: int) -> int:
    """C's integer division, which truncates toward zero."""
    quotient = abs(a) // abs(b)
    return quotient if (a < 0) == (b < 0) else -quotient


def _mod(a: int, b: int) -> int:
    """C's remainder, which takes the dividend's sign."""
    return a - b * _div(a, b)


def _int16(value: int) -> int:
    """A value as PRExplodedTime's PRInt16 tm_year stores it."""
    return (value + 0x8000) % 0x10000 - 0x8000


def _leap(year: int) -> int:
    """IsLeapYear."""
    return int((year % 4 == 0 and year % 100 != 0) or year % 400 == 0)


def _count_days(year: int) -> int:
    """COUNT_DAYS: the days from 01/01/01 to the start of year."""
    before = year - 1
    return before * 365 + _div(before, 4) - _div(before, 100) + _div(before, 400)


def _carry(low: int, high: int, size: int) -> tuple[int, int]:
    """Bring low into 0..size-1, carrying into high, as PR_NormalizeTime does each field."""
    if 0 <= low < size:
        return low, high
    high += _div(low, size)
    low = _mod(low, size)
    if low < 0:
        low += size
        high -= 1
    return low, high


type _Fields = tuple[int, int, int, int, int, int]


def _normalize(fields: _Fields) -> _Fields:
    """PR_NormalizeTime with PR_GMTParameters: year, month, mday, hour, min, sec."""
    year, month, mday, hour, minute, sec = fields
    sec, minute = _carry(sec, minute, 60)
    minute, hour = _carry(minute, hour, 60)
    hour, mday = _carry(hour, mday, 24)
    if not 0 <= month < 12:  # noqa: PLR2004 - months
        year = _int16(year + _div(month, 12))
        month = _mod(month, 12)
        if month < 0:
            month += 12
            year = _int16(year - 1)
    if mday < 1:
        while mday < 1:
            month -= 1
            if month < 0:
                month, year = 11, _int16(year - 1)
            mday += _DAYS[_leap(year)][month]
    else:
        while mday > _DAYS[_leap(year)][month]:
            mday -= _DAYS[_leap(year)][month]
            month += 1
            if month > 11:  # noqa: PLR2004 - December
                month, year = 0, _int16(year + 1)
    return year, month, mday, hour, minute, sec


def _implode(fields: _Fields, offset_seconds: int) -> int:
    """PR_ImplodeTime of the fields at the zone offset, in microseconds since the epoch."""
    year, month, mday, hour, minute, sec = _normalize((*fields[:5], fields[5] - offset_seconds))
    yday = mday + _LAST_DAY[_leap(year)][month]
    days = _count_days(year) - _count_days(1970)
    seconds = days * _SECONDS_PER_DAY + yday * _SECONDS_PER_DAY + hour * 3600 + minute * 60 + sec
    return seconds * 1_000_000


class _Parse:
    """PR_ParseTimeStringToExplodedTime's state while it walks the string."""

    def __init__(self, text: bytes) -> None:
        # A C string ends at its first NUL; the zeros stand in for it past the end.
        self.s = text.split(b"\0", 1)[0] + b"\0\0\0"
        self.end = len(self.s) - 3
        self.month: int | None = None
        self.zone: tuple[int, int] | None = None
        self.zone_offset = _UNSET
        self.date = -1
        self.year = -1
        self.hour = -1
        self.min = -1
        self.sec = -1

    def digit(self, at: int) -> bool:
        return 0x30 <= self.s[at] <= 0x39  # noqa: PLR2004 - "0".."9"

    def number(self, at: int, stop: int) -> int:
        return int(self.s[at:stop])

    def digits_end(self, at: int) -> int:
        while self.digit(at):
            at += 1
        return at

    def word(self, at: int) -> None:
        """A month or zone name, matched by its first three letters in ASCII case."""
        name = bytes(self.s[at : at + 3]).lower()
        if self.month is None and name in _MONTHS:
            self.month = _MONTHS[name]
        elif self.zone is None and name in _ZONES:
            self.zone = _ZONES[name]
        elif self.zone is None and name[:2] == b"ut" and self.s[at + 2] not in _LETTERS:
            # UT is GMT, but UTx is not.
            self.zone = _ZONES[b"gmt"]

    def offset(self, at: int) -> int:
        """A +HHMM, +HH or +H offset from GMT; returns where the token scan goes on."""
        if self.zone_offset != _UNSET or self.zone not in {None, _ZONES[b"gmt"]}:
            # Only GMT takes an offset (GMT+0300), and only one.
            return at + 1
        sign = 1 if self.s[at] == ord("+") else -1
        at += 1
        stop = self.digits_end(at)
        width = stop - at
        if width == 4:  # noqa: PLR2004 - HHMM
            minutes = self.number(at, at + 2) * 60 + self.number(at + 2, stop)
        elif width in {1, 2}:
            minutes = self.number(at, stop) * 60
        else:
            return at
        self.zone_offset = sign * minutes
        self.zone = _ZONES[b"gmt"]
        return at

    def clock(self, at: int, stop: int) -> int:  # noqa: C901 - prtime.c's own branches
        """HH:MM[:SS], with AM or PM after it; returns where the token scan goes on."""
        if self.hour >= 0 and self.min >= 0:
            return at
        if stop - at > 2:  # noqa: PLR2004
            return at
        hour = self.number(at, stop)
        at = stop + 1
        stop = self.digits_end(at)
        if stop == at or stop - at > 2:  # noqa: PLR2004
            return at
        minute = self.number(at, stop)
        at = stop
        if self.s[at] == ord(":"):
            at += 1
        stop = self.digits_end(at)
        second = -1
        if stop - at > 2:  # noqa: PLR2004
            return at
        if stop > at:
            second = self.number(at, stop)
        if hour <= 12:  # noqa: PLR2004
            after = stop
            while self.s[after] in b" \t":
                after += 1
            meridiem = bytes(self.s[after : after + 2]).lower()
            if meridiem == b"pm":
                hour = 12 if hour == 12 else hour + 12  # noqa: PLR2004
            elif hour == 12 and meridiem == b"am":  # noqa: PLR2004
                hour = 0
        self.hour, self.min, self.sec = hour, minute, second
        return stop

    def numeric_date(self, at: int) -> int:  # noqa: C901, PLR0911, PLR0912 - prtime.c's own branches
        """6/16/95, 16/6/95, 6-16-95 or 95-06-05; returns where the token scan goes on."""
        if self.month is not None:
            return at
        s = at
        parts: list[int] = []
        for index in range(3):
            if index:
                if self.s[s] not in b"/-":
                    return at
                s += 1
                if not self.digit(s):
                    return at
            value = self.s[s] - 0x30
            s += 1
            if self.digit(s):
                value = value * 10 + self.s[s] - 0x30
                s += 1
            if index == 2 and self.digit(s):  # noqa: PLR2004 - the third: 4 or 5 digits
                value = value * 10 + self.s[s] - 0x30
                s += 1
                if not self.digit(s):
                    return at
                value = value * 10 + self.s[s] - 0x30
                s += 1
                if self.digit(s):
                    value = value * 10 + self.s[s] - 0x30
                    s += 1
            parts.append(value)
        if self.digit(s) or self.s[s] in _LETTERS:
            return at
        n1, n2, n3 = parts
        if n1 > 31 or n1 == 0:  # noqa: PLR2004 - YY/MM/DD
            if n2 > 12 or n3 > 31:  # noqa: PLR2004
                return at
            self.year = n1 + (2000 if n1 < 70 else 1900 if n1 < 100 else 0)  # noqa: PLR2004
            self.month, self.date = n2 - 1, n3
            return s
        if n1 > 12 and n2 > 12:  # noqa: PLR2004
            return s
        n3 += 2000 if n3 < 70 else 1900 if n3 < 100 else 0  # noqa: PLR2004
        if n1 > 12:  # noqa: PLR2004 - DD/MM/YY
            self.date, self.month, self.year = n1, n2 - 1, n3
        else:
            self.month, self.date, self.year = n1 - 1, n2, n3
        return s

    def digits(self, at: int) -> int:
        """A time, a numeric date, a year or a day; returns where the token scan goes on."""
        stop = self.digits_end(at + 1)
        after = self.s[stop]
        if after == ord(":"):
            return self.clock(at, stop)
        if after in b"/-" and self.digit(stop + 1):
            return self.numeric_date(at)
        if after in _LETTERS:
            return at
        width = stop - at
        if width in {4, 5}:
            if self.year < 0:
                self.year = self.number(at, stop)
        elif width == 2:  # noqa: PLR2004
            n = self.number(at, stop)
            if self.date < 0 and n < 32:  # noqa: PLR2004
                self.date = n
            elif self.year < 0:
                self.year = n + (2000 if n < 70 else 1900)  # noqa: PLR2004
        elif width == 1 and self.date < 0:
            self.date = self.number(at, stop)
        return at

    def run(self) -> int | None:
        """The time in microseconds, or None when the string names no full date."""
        s, rest, iterations = self.s, 0, 0
        while rest < self.end:
            iterations += 1
            if iterations > _MAX_ITERATIONS + 1:
                return None
            char = s[rest]
            if char in _LETTERS:
                self.word(rest)
            elif char in b"+-":
                rest = self.offset(rest)
            elif self.digit(rest):
                rest = self.digits(rest)
            while rest < self.end and s[rest] not in _TOKEN_END:
                rest += 1
            while True:
                while rest < self.end and s[rest] in _BETWEEN:
                    rest += 1
                # A "-" starts no token after a word before any year (30-AUG-1966),
                # nor when no digit follows it.
                if s[rest] == ord("-") and (
                    (rest > 0 and s[rest - 1] in _LETTERS and self.year < 0)
                    or not self.digit(rest + 1)
                ):
                    rest += 1
                    continue
                break
        return self.result()

    def result(self) -> int | None:
        if self.month is None or self.date == -1 or self.year == -1 or self.year > _INT16_MAX:
            return None
        # default_to_gmt: no zone is GMT.
        zone_offset, dst = self.zone or (0, 0)
        if self.zone_offset != _UNSET:
            zone_offset = self.zone_offset
        fields = _normalize(
            (
                self.year,
                self.month,
                self.date,
                max(self.hour, 0),
                max(self.min, 0),
                max(self.sec, 0),
            )
        )
        return _implode(fields, (zone_offset + dst) * 60)


def parse_time(text: str) -> int | None:
    """PR_ParseTimeString(text, PR_TRUE): microseconds since the epoch, or None on failure.

    A string naming no zone is taken as GMT.
    """
    return _Parse(text.encode("utf-8", "surrogatepass")).run()
