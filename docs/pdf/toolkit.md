# PDF Toolkit

Catalog of PDF-focused applications managed by this configuration.\
The list covers viewers, structural inspectors, content extractors, OCR engines,\
and authoring tools whose primary or substantial purpose is working with PDF documents.

**Source of truth**: each host's `apps-enable.nix`. Per-tool option flags live in `modules/apps/<name>.nix`.\
A given entry may be enabled on one host and disabled on another;\
consult the host catalog to confirm availability before relying on a specific binary.

Each entry below lists a representative invocation, optional additional invocations, upstream repository, official documentation, a one-line description, a one-line decision hint, and an upstream maintenance classification.

`Stat.` classifies upstream health as of 2026-05-09: **Maintained** (release on/after 2025-01-01), **Maintenance mode** (mature/stable; active commits but no recent tagged release), **Core utility** (foundational tooling whose release cadence does not map to the other categories), or **Deprecated** (archived, abandoned, or superseded).

Tools that complement this toolkit but do not yet have a `modules/apps/` module are catalogued in [`additional-tools-reference.md`](additional-tools-reference.md).

## View And Review

- mupdf
  - run..: `mupdf report.pdf`
  - More..:
    - inspect: `mutool info report.pdf`
    - render: `mutool draw -o page-%03d.png report.pdf 1-3`
    - clean: `mutool clean -gggg in.pdf out.pdf`
  - Repo.: <https://github.com/ArtifexSoftware/mupdf>
  - Docs.: <https://mupdf.com/docs>
  - Desc.: Lightweight PDF, XPS, and e-book viewer plus the `mutool` toolkit for scriptable inspection and rendering.
  - Use..: Small viewer plus low-level utilities in one package; reach for `mutool` when shell-scripting render or extract steps.
  - Stat.: Maintained (1.27.2, 2026-02-18).
- okular
  - run..: `okular report.pdf`
  - More..:
    - present: `okular --presentation slides.pdf`
    - print: `okular --print invoice.pdf`
    - unique: `okular --unique report.pdf`
  - Repo.: <https://invent.kde.org/graphics/okular>
  - Docs.: <https://docs.kde.org/stable5/en/okular/okular/>
  - Desc.: KDE universal document viewer with annotations, forms, presentation mode, and broad format support.
  - Use..: GUI-first review with annotations and forms; prefer over `zathura` when not keyboard-driven.
  - Stat.: Maintained (v26.04.0, 2026-04-16).
- zathura
  - run..: `zathura report.pdf`
  - More..:
    - page: `zathura -P 42 report.pdf`
    - search: `zathura -f indicator report.pdf`
    - locked: `zathura -w secret report.pdf`
  - Repo.: <https://github.com/pwmt/zathura>
  - Docs.: <https://pwmt.org/projects/zathura/documentation>
  - Desc.: Keyboard-driven document viewer with vim-like bindings, fast search, bookmarks, and SyncTeX support.
  - Use..: Long technical PDFs and LaTeX-heavy reading; prefer over `okular` when keyboard navigation matters more than annotation UI.
  - Stat.: Maintained (2026.03.27, 2026-03-27).

## Inspect And Extract

- poppler-utils
  - run..: `pdfinfo report.pdf`
  - More..:
    - text: `pdftotext -layout report.pdf -`
    - images: `pdfimages -list report.pdf`
    - merge: `pdfunite part1.pdf part2.pdf merged.pdf`
  - Repo.: <https://gitlab.freedesktop.org/poppler/poppler>
  - Docs.: <https://poppler.freedesktop.org/>
  - Desc.: Bundle of PDF utilities (`pdfinfo`, `pdftotext`, `pdftoppm`, `pdfimages`, `pdfunite`) for shell pipelines.
  - Use..: General-purpose toolbox for metadata, text, image extraction, splitting, and merging; reach for first.
  - Stat.: Maintained (poppler-26.05.0, 2026-05-03).
- pymupdf
  - run..: `pymupdf show -metadata report.pdf`
  - More..:
    - text: `pymupdf gettext -mode layout report.pdf`
    - extract: `pymupdf extract report.pdf`
  - Repo.: <https://github.com/pymupdf/PyMuPDF>
  - Docs.: <https://pymupdf.readthedocs.io/en/latest/>
  - Desc.: Python bindings for MuPDF that extract, render, and modify PDFs; CLI plus library API.
  - Use..: Layout-aware extraction and embedded-object inspection; the bridge into Python automation when shell tools fall short.
  - Stat.: Maintained (1.27.2.3, 2026-04-24).
- qpdf
  - run..: `qpdf --check report.pdf`
  - More..:
    - linearize: `qpdf --linearize in.pdf out.pdf`
    - split: `qpdf --split-pages in.pdf page-%d.pdf`
    - json: `qpdf --json in.pdf`
  - Repo.: <https://github.com/qpdf/qpdf>
  - Docs.: <https://qpdf.readthedocs.io/en/stable/>
  - Desc.: C++ library and CLI for inspecting, validating, encrypting, and rewriting PDF structure with object-level fidelity.
  - Use..: Structural rewrites and validation; prefer over `poppler-utils` when preserving or rewriting PDF structure rather than rendering content.
  - Stat.: Maintained (v12.3.2, 2026-01-24).

## OCR And Searchable Output

- ocrmypdf
  - run..: `ocrmypdf scan.pdf searchable.pdf`
  - More..:
    - deskew: `ocrmypdf --deskew --rotate-pages scan.pdf searchable.pdf`
    - sidecar: `ocrmypdf --skip-text --sidecar scan.txt scan.pdf searchable.pdf`
    - redo: `ocrmypdf --redo-ocr scan.pdf searchable.pdf`
  - Repo.: <https://github.com/ocrmypdf/OCRmyPDF>
  - Docs.: <https://ocrmypdf.readthedocs.io/en/latest/>
  - Desc.: Adds a searchable OCR text layer to scanned PDFs while preserving the original page image.
  - Use..: Scanned PDF input; prefer over raw `tesseract` when the source is already a PDF.
  - Stat.: Maintained (v17.4.1, 2026-04-06).
- tesseract
  - run..: `tesseract receipt.png stdout`
  - More..:
    - pdf: `tesseract receipt.png receipt pdf`
    - tuned: `tesseract receipt.png stdout --psm 6 -l eng`
    - hocr: `tesseract receipt.png receipt hocr`
  - Repo.: <https://github.com/tesseract-ocr/tesseract>
  - Docs.: <https://tesseract-ocr.github.io/tessdoc/>
  - Desc.: Open-source OCR engine with 100+ language models, page segmentation modes, and hOCR/TSV/ALTO/PDF output.
  - Use..: Image-first OCR or OCR debugging; prefer over `ocrmypdf` when the input is a cropped image or you want raw OCR formats.
  - Stat.: Maintained (5.5.2, 2025-12-26).

## Generate From Other Sources

- pandoc
  - run..: `pandoc notes.md -o notes.pdf`
  - More..:
    - cite: `pandoc paper.md --citeproc --bibliography refs.bib -o paper.pdf`
    - xelatex: `pandoc report.md --pdf-engine=xelatex -o report.pdf`
    - docx: `pandoc notes.md -t docx -o notes.docx`
  - Repo.: <https://github.com/jgm/pandoc>
  - Docs.: <https://pandoc.org/MANUAL.html>
  - Desc.: Universal document converter between Markdown, LaTeX, HTML, DOCX, PDF, and many more formats with citation and template support.
  - Use..: Source is Markdown, HTML, or citation-heavy prose and a PDF is the target; not for editing an existing PDF in place.
  - Stat.: Maintained (3.9.0.2, 2026-03-19).

## Decision Guide

- Existing PDF, shell-first inspection: start with `poppler-utils`.
- Existing PDF, structural rewrite or validation: use `qpdf`.
- Existing PDF, lightweight render or scriptable extraction: use `mupdf` (`mutool`).
- Existing PDF, layout-aware CLI extraction or scripted parsing: use `pymupdf`.
- Existing PDF, ML-driven Markdown/JSON for RAG pipelines: see [`additional-tools-reference.md`](additional-tools-reference.md) for `marker` and `docling`.
- Existing PDF, layout-aware Markdown for RAG pipelines without bundled ML models: see [`additional-tools-reference.md`](additional-tools-reference.md) for `pymupdf4llm`.
- Scanned PDF needing a searchable text layer: use `ocrmypdf`.
- Image OCR or OCR format debugging: use `tesseract`.
- Full-featured GUI review with annotations: use `okular`.
- Keyboard-centric reading or LaTeX workflows: use `zathura`.
- Authoring a PDF from Markdown, HTML, or citations: use `pandoc`.
