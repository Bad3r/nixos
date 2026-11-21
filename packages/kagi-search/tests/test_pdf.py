# Copyright (c) 2026 Bad3r
"""PDF pages rendered by the real renderer, and how its failures are reported."""

import contextlib
import io
import json
import math
import os
import random
import socket
import subprocess
import sys
import tempfile
import time
import unittest
import unittest.mock
from pathlib import Path
from typing import override

from kagi_search import pdf
from PIL import Image

from tests import pdfs, sandbox

RED = (255, 0, 0)
WHITE = (255, 255, 255)
BLUE = (0, 0, 255)
# A red box in the top left quarter of the first page; the second page is all blue.
BOX = (100, 600, 200, 100)
TWO_PAGES = pdfs.document(
    [pdfs.rectangle((1, 0, 0), BOX), pdfs.rectangle((0, 0, 1), (0, 0, *pdfs.LETTER))]
)
NOISE_SIDE = 1024
STALL_SLACK_SECONDS = 10
FLOOD_LIMIT_BYTES = 256 * 1024
LOWER_CPU_SECONDS = 10
# A parent that lowers its own CPU limit, soft only or hard too, renders a page, and
# then has a stand-in child report the limit it runs under.
LIMIT_PROGRAM = """\
import pathlib, resource, sys, tempfile, time
sys.path[:0] = {path!r}
from kagi_search import pdf
hard = resource.getrlimit(resource.RLIMIT_CPU)[1]
resource.setrlimit(resource.RLIMIT_CPU, ({lower}, hard if sys.argv[1] == "soft" else {lower}))
data = sys.stdin.buffer.read()
print(pdf.render_page(data, 0, time.monotonic() + 30).mime)
with tempfile.TemporaryDirectory() as work:
    pdf.SCRIPT = str(pathlib.Path(work, "child.py"))
    pathlib.Path(pdf.SCRIPT).write_text({child!r})
    try:
        pdf.render_page(data, 0, time.monotonic() + 30)
    except pdf.RenderError as error:
        print(error)
"""
# A stand-in child that reports what it can reach: a file of the test's, a listening
# port of the test's, the user's home, and its environment.
PROBE_PROGRAM = """\
import json, os, pathlib, socket
seen = {{"env": sorted(os.environ)}}
try:
    seen["file"] = pathlib.Path({secret!r}).read_text()
except OSError as error:
    seen["file"] = type(error).__name__
try:
    socket.create_connection(("127.0.0.1", {port}), 2).close()
    seen["net"] = "connected"
except OSError as error:
    seen["net"] = type(error).__name__
seen["home"] = "present" if pathlib.Path("/home").exists() else "missing"
print(json.dumps({{"error": json.dumps(seen)}}))
"""
REPORT_CPU_LIMIT = (
    "import json, resource\n"
    'print(json.dumps({"error": str(resource.getrlimit(resource.RLIMIT_CPU)[0])}))\n'
)


def soon() -> float:
    """Return a deadline the renderer meets."""
    return time.monotonic() + pdf.RENDER_TIMEOUT_SECONDS


def picture(image: pdf.Image) -> Image.Image:
    """Return the rendered image decoded."""
    return Image.open(io.BytesIO(image.data))


def noise() -> bytes:
    """Return a page filled by an inline image of random pixels, which PNG cannot shrink."""
    width, height = pdfs.LETTER
    pixels = random.Random(0).randbytes(NOISE_SIDE * NOISE_SIDE * 3)  # noqa: S311 - a fixture
    head = f"q {width} 0 0 {height} 0 0 cm BI /W {NOISE_SIDE} /H {NOISE_SIDE} /CS /RGB /BPC 8 ID "
    return head.encode() + pixels + b" EI Q"


class RenderTest(unittest.TestCase):
    """Pages of real documents, rendered in the child process."""

    @classmethod
    @override
    def setUpClass(cls) -> None:
        sandbox.require()

    def test_a_page_is_rendered_where_its_content_is(self) -> None:
        """The box is red at its place and the page white beside it, at the limits' size."""
        image = pdf.render_page(TWO_PAGES, 0, soon())
        self.assertEqual(image.mime, "image/png")
        shown = picture(image)
        width, height = shown.size
        self.assertLessEqual(max(width, height), pdf.MAX_DIMENSION)
        self.assertGreater(width, pdf.MAX_DIMENSION // 2)
        scale = width / pdfs.LETTER[0]
        left, bottom, box_width, box_height = BOX
        inside = (
            round((left + box_width / 2) * scale),
            round((pdfs.LETTER[1] - bottom - box_height / 2) * scale),
        )
        self.assertEqual(shown.getpixel(inside), RED)
        self.assertEqual(shown.getpixel((width // 2, height - 10)), WHITE)
        self.assertTrue(image.data_url().startswith("data:image/png;base64,iVBOR"))

    def test_the_page_number_selects_the_page(self) -> None:
        """Page 1 is the second page."""
        shown = picture(pdf.render_page(TWO_PAGES, 1, soon()))
        self.assertEqual(shown.getpixel((shown.size[0] // 2, shown.size[1] // 2)), BLUE)

    def test_a_raster_page_becomes_a_jpeg(self) -> None:
        """A page whose PNG is large is returned as the smaller JPEG."""
        image = pdf.render_page(pdfs.document([noise()]), 0, soon())
        self.assertEqual(image.mime, "image/jpeg")
        self.assertEqual(picture(image).format, "JPEG")

    def test_pages_of_odd_sizes_stay_within_the_limits(self) -> None:
        """A tiny, a huge, and a thread-thin page each render to a bounded image."""
        for size in ((10, 10), (14400, 14400), (1, 14400)):
            with self.subTest(size=size):
                document = pdfs.document([pdfs.rectangle((1, 0, 0), (0, 0, *size))], size=size)
                width, height = picture(pdf.render_page(document, 0, soon())).size
                self.assertLessEqual(max(width, height), pdf.MAX_DIMENSION)
                self.assertGreaterEqual(min(width, height), 1)

    def test_what_cannot_be_rendered_says_why(self) -> None:
        """Each document that yields no image is refused with its own reason."""
        box = pdfs.rectangle((1, 0, 0), BOX)
        cases = [
            (TWO_PAGES, 2, "page 2 is past the last page; the PDF has 2 pages"),
            (TWO_PAGES, 999, "page 999 is past the last page"),
            (pdfs.document([box], trailer=pdfs.NEEDS_PASSWORD), 0, "the PDF needs a password"),
            (pdfs.document([box], trailer=pdfs.UNKNOWN_SECURITY), 0, "a scheme the renderer"),
            (b"<html>not a pdf</html>", 0, "not a PDF the renderer can read"),
            (b"", 0, "not a PDF the renderer can read"),
            (TWO_PAGES[: len(TWO_PAGES) // 3], 0, "not a PDF the renderer can read"),
        ]
        for document, pageno, reason in cases:
            with self.subTest(reason=reason), self.assertRaisesRegex(pdf.RenderError, reason):
                pdf.render_page(document, pageno, soon())

    def test_a_filled_in_form_field_is_in_the_image(self) -> None:
        """A checked form field shows its mark, which PDFium draws only for a loaded form."""
        shown = picture(pdf.render_page(pdfs.checked_form((1, 0, 0), BOX), 0, soon()))
        scale = shown.size[0] / pdfs.LETTER[0]
        left, bottom, box_width, box_height = BOX
        inside = (
            round((left + box_width / 2) * scale),
            round((pdfs.LETTER[1] - bottom - box_height / 2) * scale),
        )
        self.assertEqual(shown.getpixel(inside), RED)

    def test_no_render_starts_past_the_deadline(self) -> None:
        """A deadline already passed starts no renderer."""
        with (
            unittest.mock.patch.object(pdf.subprocess, "run") as run,
            self.assertRaisesRegex(pdf.RenderError, "not started"),
        ):
            pdf.render_page(TWO_PAGES, 0, time.monotonic() - 1)
        run.assert_not_called()


class ChildTestCase(unittest.TestCase):
    """render_page run on a stand-in for the child: a real process under the real limits."""

    @classmethod
    @override
    def setUpClass(cls) -> None:
        sandbox.require()

    @override
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.work = Path(tmp.name)

    def running(self) -> bool:
        """Tell whether a process still runs this test's stand-in child."""
        script = str(self.work / "child.py").encode()
        for entry in Path("/proc").iterdir():
            if entry.name.isdigit():
                with contextlib.suppress(OSError):
                    if script in (entry / "cmdline").read_bytes():
                        return True
        return False

    def failure(self, program: str, *, seconds: float = pdf.RENDER_TIMEOUT_SECONDS) -> str:
        """Return the reason render_page gives when the child runs the program instead."""
        script = self.work / "child.py"
        script.write_text(program, encoding="utf-8")
        with (
            unittest.mock.patch.object(pdf, "SCRIPT", str(script)),
            unittest.mock.patch.object(pdf, "RENDER_TIMEOUT_SECONDS", seconds),
            self.assertRaises(pdf.RenderError) as raised,
        ):
            pdf.render_page(TWO_PAGES, 0, time.monotonic() + seconds)
        return str(raised.exception)


class ChildFailureTest(ChildTestCase):
    """A renderer that dies, stalls, or outgrows its limits is a reported failure."""

    def test_a_stalled_child_is_killed(self) -> None:
        """A child past the timeout is reported and no longer runs."""
        started = time.monotonic()
        reason = self.failure("import time\ntime.sleep(60)\n", seconds=1)
        self.assertEqual(reason, "the renderer took longer than 1 s")
        self.assertLess(time.monotonic() - started, STALL_SLACK_SECONDS)
        until = time.monotonic() + STALL_SLACK_SECONDS
        while self.running() and time.monotonic() < until:
            time.sleep(0.05)
        self.assertFalse(self.running())

    def test_a_crashed_child_names_its_signal(self) -> None:
        """A child killed by a signal is reported by the signal's name."""
        program = "import os, signal\nos.kill(os.getpid(), signal.SIGSEGV)\n"
        self.assertEqual(self.failure(program), "the renderer was killed by SIGSEGV")

    def test_a_child_past_the_memory_limit_fails(self) -> None:
        """An allocation past the limit fails in the child, which reports it and exits."""
        reason = self.failure(f"hog = bytearray({pdf.MEMORY_LIMIT_BYTES})\n")
        self.assertRegex(reason, r"^the renderer exited 1: .*MemoryError$")

    def test_a_child_cannot_flood_its_output(self) -> None:
        """Output past the size limit ends the child; the parent reads no more than the limit."""
        program = "import sys\nwhile True:\n    sys.stdout.buffer.write(bytes(65536))\n"
        with unittest.mock.patch.object(pdf, "MAX_OUTPUT_BYTES", FLOOD_LIMIT_BYTES):
            reason = self.failure(program)
        self.assertIn("File too large", reason)

    def test_only_the_end_of_long_complaints_is_reported(self) -> None:
        """A child that writes much to stderr is reported by its last words."""
        program = "import sys\nsys.stderr.write('x' * 100_000 + ' the end')\nsys.exit(3)\n"
        reason = self.failure(program)
        self.assertTrue(reason.startswith("the renderer exited 3: x"))
        self.assertTrue(reason.endswith(" the end"))
        self.assertLess(len(reason), 2 * pdf.STDERR_TAIL_CHARS)

    def test_an_answer_without_an_image_is_refused(self) -> None:
        """Output that is no JSON line with an image after it is not taken for an image."""
        for answer in (b"", b"garbage", b'{"mime": "image/png"}\n', b"[]\nxx", b'{"mime": 1}\nxx'):
            with self.subTest(answer=answer):
                program = f"import sys\nsys.stdout.buffer.write({answer!r})\n"
                self.assertIn("the renderer's answer", self.failure(program))

    def test_a_sandbox_that_cannot_start_is_reported(self) -> None:
        """A missing bubblewrap, or no room for the child's output, is a render failure."""
        with (
            unittest.mock.patch.object(pdf, "BWRAP", str(self.work / "missing")),
            self.assertRaisesRegex(pdf.RenderError, "could not run"),
        ):
            pdf.render_page(TWO_PAGES, 0, soon())
        with (
            unittest.mock.patch.object(
                pdf.tempfile, "TemporaryFile", side_effect=OSError(28, "full")
            ),
            self.assertRaisesRegex(pdf.RenderError, "could not run"),
        ):
            pdf.render_page(TWO_PAGES, 0, soon())

    def test_the_child_reaches_nothing_but_its_input(self) -> None:
        """The child reads no file of the user's, opens no connection, and inherits no variable."""
        secret = self.work / "secret"
        secret.write_text("private")
        with socket.create_server(("127.0.0.1", 0)) as server:
            server.settimeout(0)
            program = PROBE_PROGRAM.format(secret=str(secret), port=server.getsockname()[1])
            with unittest.mock.patch.dict(os.environ, {"KAGI_SEARCH_TEST_TOKEN": "private"}):
                seen = json.loads(self.failure(program))
            with self.assertRaises(BlockingIOError):
                server.accept()
        self.assertEqual(seen["file"], "FileNotFoundError")
        self.assertNotEqual(seen["net"], "connected")
        self.assertNotIn("KAGI_SEARCH_TEST_TOKEN", seen["env"])
        self.assertNotIn("HOME", seen["env"])
        self.assertEqual(seen["home"], "missing")

    def test_a_lower_limit_already_in_force_stays(self) -> None:
        """Under a CPU limit below the renderer's own, hard or only soft, the child keeps it."""
        program = LIMIT_PROGRAM.format(
            path=sys.path, lower=LOWER_CPU_SECONDS, child=REPORT_CPU_LIMIT
        )
        for which in ("soft", "hard"):
            with self.subTest(which=which):
                ran = subprocess.run(
                    [sys.executable, "-IB", "-c", program, which],
                    input=TWO_PAGES,
                    capture_output=True,
                    timeout=60,
                    check=False,
                )
                expected = f"image/png\n{LOWER_CPU_SECONDS}\n".encode()
                self.assertEqual((ran.returncode, ran.stdout, ran.stderr), (0, expected, b""))


class ScaleTest(unittest.TestCase):
    """The zoom that fits a page to the image limits."""

    def test_every_size_fits_the_limits(self) -> None:
        """No page size renders past the longest side, the patch count, or the zoom limit."""
        sides = (1, 72, 595, 612, 792, 842, 1191, 14400)
        for width in sides:
            for height in sides:
                with self.subTest(width=width, height=height):
                    scale = pdf.scale_for(width, height)
                    across, down = math.ceil(width * scale), math.ceil(height * scale)
                    self.assertLessEqual(scale, pdf.MAX_SCALE)
                    self.assertLessEqual(max(across, down), pdf.MAX_DIMENSION)
                    patches = math.ceil(across / pdf.PATCH_SIZE) * math.ceil(down / pdf.PATCH_SIZE)
                    self.assertLessEqual(patches, pdf.MAX_PATCHES)

    def test_a_letter_page_is_legible(self) -> None:
        """A US Letter page renders above 150 dpi."""
        self.assertGreater(pdf.scale_for(*pdfs.LETTER) * 72, 150)
