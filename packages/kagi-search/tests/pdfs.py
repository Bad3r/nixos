# Copyright (c) 2026 Bad3r
"""PDF documents built for the tests: filled rectangles, and no text."""

from __future__ import annotations

LETTER = (612, 792)
# A password check no password passes: the owner and user entries are not derived from one.
NEEDS_PASSWORD = (
    "/Encrypt << /Filter /Standard /V 1 /R 2 /P -4 "
    f"/O <{'11' * 32}> /U <{'22' * 32}> >> /ID [<{'33' * 16}> <{'33' * 16}>]"
)
UNKNOWN_SECURITY = f"/Encrypt << /Filter /Elsewhere /V 1 >> /ID [<{'33' * 16}> <{'33' * 16}>]"


def rectangle(rgb: tuple[float, float, float], box: tuple[int, int, int, int]) -> bytes:
    """Return a page's content: box (x, y, width, height from the bottom left) filled with rgb."""
    red, green, blue = rgb
    x, y, width, height = box
    return f"{red:g} {green:g} {blue:g} rg {x} {y} {width} {height} re f".encode()


def stream(content: bytes, entries: str = "") -> bytes:
    """Return a stream object's body holding the content."""
    return b"<< %s /Length %d >>\nstream\n%s\nendstream" % (
        entries.encode(),
        len(content),
        content,
    )


def assemble(objects: list[bytes], trailer: str = "") -> bytes:
    """Return a PDF of the objects, numbered from 1, whose first is the catalog."""
    out = b"%PDF-1.4\n"
    offsets: list[int] = []
    for number, body in enumerate(objects, 1):
        offsets.append(len(out))
        out += b"%d 0 obj\n%s\nendobj\n" % (number, body)
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
    out += b"".join(b"%010d 00000 n \n" % offset for offset in offsets)
    out += f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R {trailer} >>\n".encode()
    return out + b"startxref\n%d\n%%%%EOF\n" % xref


def document(pages: list[bytes], *, size: tuple[int, int] = LETTER, trailer: str = "") -> bytes:
    """Return a PDF whose pages have the given contents and size in points."""
    width, height = size
    kids = " ".join(f"{3 + 2 * index} 0 R" for index in range(len(pages)))
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        f"<< /Type /Pages /Kids [{kids}] /Count {len(pages)} >>".encode(),
    ]
    for index, content in enumerate(pages):
        objects.append(
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {width} {height}] "
            f"/Contents {4 + 2 * index} 0 R >>".encode()
        )
        objects.append(stream(content))
    return assemble(objects, trailer)


def checked_form(rgb: tuple[float, float, float], box: tuple[int, int, int, int]) -> bytes:
    """Return a one-page PDF whose only mark is a checked form field: box filled with rgb."""
    x, y, width, height = box
    width_page, height_page = LETTER
    form = f"/Type /XObject /Subtype /Form /BBox [0 0 {width} {height}]"
    return assemble(
        [
            b"<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [5 0 R] >> >>",
            b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {width_page} {height_page}] "
            "/Contents 4 0 R /Annots [5 0 R] >>".encode(),
            stream(b""),
            f"<< /Type /Annot /Subtype /Widget /FT /Btn /T (box) /V /On /AS /On /F 4 /P 3 0 R "
            f"/Rect [{x} {y} {x + width} {y + height}] "
            "/AP << /N << /On 6 0 R /Off 7 0 R >> >> >>".encode(),
            stream(rectangle(rgb, (0, 0, width, height)), form),
            stream(b"", form),
        ]
    )
