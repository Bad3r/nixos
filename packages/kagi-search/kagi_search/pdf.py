# Copyright (c) 2026 Bad3r
"""PDF pages rendered to images for web.run's screenshot.

PDFium parses the fetched document in a child process that bubblewrap
confines and resource limits bound, so a document that crashes, stalls,
bloats, or takes over the renderer costs one screenshot and not the call: the
child has no network, no environment, and no files but the Nix store. Run as
a script, this file is that child: it imports nothing of kagi_search.
"""

from __future__ import annotations

import base64
import contextlib
import importlib
import io
import json
import math
import resource
import signal
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from typing import TYPE_CHECKING, Protocol, cast

if TYPE_CHECKING:
    from collections.abc import Callable
    from typing import IO

    from PIL.Image import Image as Picture

# Codex's limits for a high-detail image (codex-rs/utils/image); a page
# rendered within them reaches the model without being resampled.
MAX_DIMENSION = 2048
MAX_PATCHES = 2500
PATCH_SIZE = 32
# 288 dpi: small pages are not enlarged past it.
MAX_SCALE = 4.0
# Past this size a page is mostly raster content, which JPEG holds in a fraction
# of the bytes; every later model request carries the image again.
MAX_PNG_BYTES = 1024 * 1024
JPEG_QUALITY = 85

RENDER_TIMEOUT_SECONDS = 30.0
MEMORY_LIMIT_BYTES = 4 * 1024**3
# The child's answer and its stderr each go to a file it cannot grow past this,
# several times the largest image the limits above allow.
MAX_OUTPUT_BYTES = 32 * 1024 * 1024
STDERR_TAIL_BYTES = 4096
# The child's answer starts with one short JSON line; the image formats it may
# name, with the bytes each starts with.
MAX_HEADER_BYTES = 512
IMAGE_SIGNATURES = {"image/png": b"\x89PNG\r\n\x1a\n", "image/jpeg": b"\xff\xd8\xff"}
STDERR_TAIL_CHARS = 300
# The program the child runs: this file.
SCRIPT = __file__
BWRAP = "@bwrap@"
# All the child may read: the interpreter, its libraries, and PDFium live here.
STORE = "/nix/store"
# A shell's exit status for a command a signal killed, which bubblewrap passes on.
SIGNAL_EXIT_BASE = 128
# PDFium's FPDF_GetLastError codes for a document that needs a password and
# for one protected by a scheme PDFium does not implement.
PDFIUM_PASSWORD = 4
PDFIUM_SECURITY = 5


class RenderError(Exception):
    """A PDF page could not be rendered to an image."""


class _Bitmap(Protocol):
    def to_pil(self) -> Picture: ...


class _Page(Protocol):
    def get_size(self) -> tuple[float, float]: ...

    def render(self, *, scale: float) -> _Bitmap: ...


class _Document(Protocol):
    def init_forms(self) -> object: ...

    def __len__(self) -> int: ...

    def __getitem__(self, index: int) -> _Page: ...


class _Pdfium(Protocol):
    """What the renderer uses of pypdfium2, which ships no types."""

    PdfDocument: Callable[[bytes], _Document]
    PdfiumError: type[Exception]


@dataclass(frozen=True)
class Image:
    """A rendered page: its media type and encoded bytes."""

    mime: str
    data: bytes

    def data_url(self) -> str:
        """Return the image as a data: URL."""
        return f"data:{self.mime};base64,{base64.b64encode(self.data).decode('ascii')}"


def scale_for(width: float, height: float) -> float:
    """Return the zoom at which a page of that size in points fills the image limits."""
    scale = min(
        MAX_SCALE,
        MAX_DIMENSION / max(width, height),
        math.sqrt(MAX_PATCHES * PATCH_SIZE**2 / (width * height)),
    )
    while _patches(width * scale) * _patches(height * scale) > MAX_PATCHES:
        scale *= 0.99
    return scale


def _patches(pixels: float) -> int:
    return math.ceil(math.ceil(pixels) / PATCH_SIZE)


def render_page(data: bytes, pageno: int, until: float) -> Image:
    """Return the PDF's zero-indexed page as an image, rendered by the monotonic time until.

    Raises RenderError naming the reason: a page past the last one, a document
    that needs a password or is no PDF, or a renderer that failed.
    """
    timeout = min(RENDER_TIMEOUT_SECONDS, until - time.monotonic())
    if timeout <= 0:
        msg = "not started: the call's deadline is near"
        raise RenderError(msg)
    try:
        with tempfile.TemporaryFile() as answer, tempfile.TemporaryFile() as complaints:
            ran = subprocess.run(
                _command(pageno),
                input=data,
                stdout=answer,
                stderr=complaints,
                timeout=timeout,
                check=False,
                preexec_fn=_limit,
            )
            if ran.returncode != 0:
                raise RenderError(_crash(ran.returncode, complaints))
            answer.seek(0)
            return _parse(answer.read(MAX_OUTPUT_BYTES))
    except subprocess.TimeoutExpired:
        msg = f"the renderer took longer than {timeout:.0f} s"
        raise RenderError(msg) from None
    except (OSError, subprocess.SubprocessError) as error:
        msg = f"the renderer could not run: {error}"
        raise RenderError(msg) from None


def _command(pageno: int) -> list[str]:
    """Return the child's command line: this file, run where it can reach nothing else."""
    return [
        BWRAP,
        "--unshare-all",
        "--die-with-parent",
        "--new-session",
        "--clearenv",
        *("--ro-bind", STORE, STORE),
        *("--ro-bind", SCRIPT, SCRIPT),
        *("--dev", "/dev"),
        "--",
        *(sys.executable, "-IB", SCRIPT, str(pageno)),
    ]


def _limit() -> None:
    """Bound the child's memory, CPU time, and output, and keep it from dumping core.

    A limit the process already runs under stays when it is the lower one.
    """
    limits = (
        (resource.RLIMIT_AS, MEMORY_LIMIT_BYTES),
        (resource.RLIMIT_CPU, math.ceil(RENDER_TIMEOUT_SECONDS)),
        (resource.RLIMIT_FSIZE, MAX_OUTPUT_BYTES),
        (resource.RLIMIT_CORE, 0),
    )
    for kind, limit in limits:
        soft, _ = resource.getrlimit(kind)
        bound = limit if soft == resource.RLIM_INFINITY else min(limit, soft)
        resource.setrlimit(kind, (bound, bound))


def _crash(code: int, complaints: IO[bytes]) -> str:
    number = -code if code < 0 else code - SIGNAL_EXIT_BASE
    if number > 0:
        try:
            how = f"was killed by {signal.Signals(number).name}"
        except ValueError:
            how = f"was killed by signal {number}"
    else:
        how = f"exited {code}"
    complaints.seek(max(complaints.seek(0, 2) - STDERR_TAIL_BYTES, 0))
    tail = " ".join(complaints.read().decode("utf-8", "replace").split())[-STDERR_TAIL_CHARS:]
    return f"the renderer {how}: {tail}" if tail else f"the renderer {how}"


def _parse(stdout: bytes) -> Image:
    """Return the image of a child's answer: a JSON line, then the image bytes.

    The child may be under a hostile document's control, so nothing of its answer
    is taken on trust: the line is short, and the image is a PNG or JPEG that
    starts as one.
    """
    head, _, body = stdout.partition(b"\n")
    answer: object = None
    if len(head) <= MAX_HEADER_BYTES:
        with contextlib.suppress(ValueError, RecursionError):
            answer = json.loads(head)
    if not isinstance(answer, dict):
        msg = "the renderer's answer is not understood"
        raise RenderError(msg)
    fields = cast("dict[str, object]", answer)
    error, mime = fields.get("error"), fields.get("mime")
    if isinstance(error, str):
        raise RenderError(error)
    signature = IMAGE_SIGNATURES.get(mime) if isinstance(mime, str) else None
    if not isinstance(mime, str) or signature is None or not body.startswith(signature):
        msg = "the renderer's answer has no image"
        raise RenderError(msg)
    return Image(mime, body)


# The child


def _render(data: bytes, pageno: int) -> Image:
    # Loaded here: only the child links PDFium.
    pdfium = cast("_Pdfium", importlib.import_module("pypdfium2"))
    try:
        document = pdfium.PdfDocument(data)
    except pdfium.PdfiumError as error:
        code: object = getattr(error, "err_code", None)
        if code == PDFIUM_PASSWORD:
            msg = "the PDF needs a password"
        elif code == PDFIUM_SECURITY:
            msg = "the PDF is protected by a scheme the renderer does not support"
        else:
            msg = f"not a PDF the renderer can read: {error}"
        raise RenderError(msg) from None
    try:
        # Before any page is loaded, or filled-in form fields are left out of the image.
        document.init_forms()
    except pdfium.PdfiumError as error:
        msg = f"the PDF's form cannot be loaded: {error}"
        raise RenderError(msg) from None
    pages = len(document)
    if pageno >= pages:
        msg = f"page {pageno} is past the last page; the PDF has {pages} pages, numbered from 0"
        raise RenderError(msg)
    try:
        page = document[pageno]
        width, height = page.get_size()
        if width <= 0 or height <= 0:
            msg = f"page {pageno} has no area ({width:g} x {height:g} points)"
            raise RenderError(msg)
        picture = page.render(scale=scale_for(width, height)).to_pil().convert("RGB")
    except pdfium.PdfiumError as error:
        msg = f"page {pageno} cannot be rendered: {error}"
        raise RenderError(msg) from None
    png = io.BytesIO()
    picture.save(png, "PNG")
    if png.tell() <= MAX_PNG_BYTES:
        return Image("image/png", png.getvalue())
    jpeg = io.BytesIO()
    picture.save(jpeg, "JPEG", quality=JPEG_QUALITY)
    if jpeg.tell() < png.tell():
        return Image("image/jpeg", jpeg.getvalue())
    return Image("image/png", png.getvalue())


def _seal() -> None:
    """Keep this process from starting another, before it reads the document.

    The memory and CPU limits count per process, so a renderer that could fork
    would multiply them.
    """
    resource.setrlimit(resource.RLIMIT_NPROC, (0, 0))


def main() -> int:
    """Render the page numbered by argv[1] of the PDF on stdin.

    Prints a JSON line, {"mime": ...} followed by the image bytes or
    {"error": ...}; any other end is a crash the parent reports.
    """
    _seal()
    pageno = int(sys.argv[1])
    data = sys.stdin.buffer.read()
    try:
        image = _render(data, pageno)
    except RenderError as error:
        sys.stdout.buffer.write(json.dumps({"error": str(error)}).encode())
        return 0
    sys.stdout.buffer.write(json.dumps({"mime": image.mime}).encode() + b"\n" + image.data)
    return 0


if __name__ == "__main__":
    sys.exit(main())
