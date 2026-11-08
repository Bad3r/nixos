# Copyright (c) 2026 Bad3r
"""Cookie dates against NSPR's PR_ParseTimeString, which Gecko's GetExpiry calls.

Expected values come from NSPR's own known answers (nsprpub/pr/tests/parsetm.c),
the web-platform tests Firefox 158 passes (cookies/attributes/expires.html),
RFC 6265 and, when the package check provides it, NSPR 4.40 itself.
"""

import calendar
import ctypes
import os
import random
import unittest

from browser_fetch import dates

US = 1_000_000


def gmt(*fields: int) -> int:
    """A GMT date and time, in microseconds since the epoch."""
    return calendar.timegm((*fields, 0, 0, 0)) * US


class KnownAnswerTest(unittest.TestCase):
    """Dates whose times are fixed by NSPR's tests or by their calendar."""

    def test_nspr_known_answers(self) -> None:
        """parsetm.c's KnownAnswerTest; each string names its zone, so default_to_gmt is moot.

        The last two carry unnormalized fields over: second 60 and hour 36.
        """
        for text, expected in (
            ("Mon, 15 Oct 2007 19:45:00 GMT", 1192477500000000),
            ("15 Oct 07 19:45 GMT", 1192477500000000),
            ("Mon Oct 15 12:45 PDT 2007", 1192477500000000),
            ("16 Oct 2007 4:45-JST (Tuesday)", 1192477500000000),
            ("Mon Oct 15 12:44:60 PDT 2007", 1192477500000000),
            ("Sun Oct 14 36:45 PDT 2007", 1192477500000000),
            ("Mon, 15 Oct 2007 19:45:23 GMT", 1192477523000000),
        ):
            with self.subTest(text=text):
                self.assertEqual(dates.parse_time(text), expected)

    def test_rfc_6265_dates(self) -> None:
        """RFC 6265's sane-cookie-date and the asctime form, which section 5.1.1 also reads."""
        self.assertEqual(
            dates.parse_time("Wed, 09 Jun 2021 10:18:14 GMT"), gmt(2021, 6, 9, 10, 18, 14)
        )
        self.assertEqual(dates.parse_time("Wed Jun 09 10:18:14 2027"), gmt(2027, 6, 9, 10, 18, 14))

    def test_web_platform_expires(self) -> None:
        """cookies/attributes/expires.html, which Firefox 158 passes: each date parses.

        Month-first, asctime and Date.prototype.toString() forms all read as
        the same instant; the GMT-0700 offset moves it seven hours.
        """
        for text, expected in (
            ("Fri, 01 Jan 2038 00:00:00 GMT", gmt(2038, 1, 1, 0, 0, 0)),
            ("Fri 01 Jan 2038 00:00:00 GMT, baz=qux", gmt(2038, 1, 1, 0, 0, 0)),
            ("Fri, 07 Aug 2007 08:04:19 GMT", gmt(2007, 8, 7, 8, 4, 19)),
            ("Thu, 10 Apr 1980 16:33:12 GMT", gmt(1980, 4, 10, 16, 33, 12)),
            ("Fri Jan 01 2038 00:00:00 GMT", gmt(2038, 1, 1, 0, 0, 0)),
            ("Apr 10 1980 16:33:12 GMT", gmt(1980, 4, 10, 16, 33, 12)),
            (
                "Thu Apr 10 1980 16:33:12 GMT-0700 (Pacific Daylight Time)",
                gmt(1980, 4, 10, 23, 33, 12),
            ),
            ("Fri Jan 01 03:14:07 2038", gmt(2038, 1, 1, 3, 14, 7)),
        ):
            with self.subTest(text=text):
                self.assertEqual(dates.parse_time(text), expected)

    def test_gecko_reads_more_than_rfc_6265(self) -> None:
        """Forms section 5.1.1 refuses and NSPR takes, as its header comment lists them.

        A numeric date, PM, a zone name and a day past the month's end
        (carried into the next month) all parse.
        """
        for text, expected in (
            ("06/21/95 04:24:34 PM", gmt(1995, 6, 21, 16, 24, 34)),
            ("22-AUG-1993 10:59pm", gmt(1993, 8, 22, 22, 59, 0)),
            ("Wed, 09 Jun 2027 10:18:14 EST", gmt(2027, 6, 9, 15, 18, 14)),
            ("30 Feb 2027 00:00:00 GMT", gmt(2027, 3, 2, 0, 0, 0)),
        ):
            with self.subTest(text=text):
                self.assertEqual(dates.parse_time(text), expected)

    def test_no_full_date_fails(self) -> None:
        """Without a month, a day and a year, or past year 32767, there is no date."""
        for text in ("bad", "soon", "", "Jun 2027", "09 2027 10:18:14", "1 Jan 32768"):
            with self.subTest(text=text):
                self.assertIsNone(dates.parse_time(text))


NSPR = os.environ.get("BROWSER_FETCH_TEST_NSPR", "")
_PIECES = (
    "Mon", "Thu", "Sun", "Jan", "Feb", "Jun", "june", "Sep", "Dec",
    "UT", "UTC", "GMT", "PST", "PDT", "EST", "JST", "BST", "NST", "MET",
    "am", "pm", "AM", "PM",
    "0", "1", "9", "00", "09", "12", "13", "29", "31", "32", "59", "60", "69", "70", "99",
    "100", "1980", "2027", "9999", "32767", "32768", "99999", "0000", "123456",
    "10:18:14", "1:2", "23:59:60", "99:99:99", "12:00", "12:30am", "1:", "1:2:", "123:4", "1:234",
    "+0200", "-0700", "+2", "-05", "+123", "-0001", "+", "-",
    "06/21/95", "21/06/95", "95-06-08", "0/0/0", "00-1-1", "13/13/13", "1/1/12345", "1-2-3x",
    ",", ";", "(", ")", "[", "]", ".", "x", "Z", "T", "é",
)  # fmt: skip
_SEPARATORS = (" ", ", ", "-", "", "/", ";", "\t")


@unittest.skipUnless(NSPR, "BROWSER_FETCH_TEST_NSPR names no libnspr4; the package check sets it")
class NsprAgreesTest(unittest.TestCase):
    """The port against NSPR 4.40 itself, on strings built from date fragments."""

    def test_same_time_or_failure(self) -> None:
        """Every string parses to NSPR's time, or fails where NSPR fails."""
        library = ctypes.CDLL(NSPR)
        parse = library.PR_ParseTimeString
        parse.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.POINTER(ctypes.c_int64)]
        parse.restype = ctypes.c_int
        pick = random.Random(6265)  # noqa: S311 - a fixed corpus, not a secret
        for _ in range(20_000):
            text = "".join(
                pick.choice(_PIECES) + pick.choice(_SEPARATORS) for _ in range(pick.randint(1, 9))
            )
            result = ctypes.c_int64()
            ok = parse(text.encode(), 1, ctypes.byref(result)) == 0
            with self.subTest(text=text):
                self.assertEqual(dates.parse_time(text), result.value if ok else None)
