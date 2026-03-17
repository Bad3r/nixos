# PDF Tooling

- This page covers the PDF-focused packages currently modeled under `modules/apps/`.
- Included here: `mupdf`, `ocrmypdf`, `okular`, `pandoc`, `poppler-utils`, `pymupdf`, `qpdf`, `tesseract`, and `zathura`.
- It intentionally excludes general tools where PDF support is incidental, such as `inkscape`, `potrace`, or browser built-in viewers.

## View And Review

### `okular`

- Use it when you want a full desktop viewer with annotations, forms, and presentation mode.
- Better fit than `zathura` when you want a GUI-first review workflow.

```bash
okular report.pdf
okular --presentation slides.pdf
okular --print invoice.pdf
```

### `zathura`

- Use it when you want a keyboard-driven viewer with fast search, page jumps, and bookmark-oriented navigation.
- Good fit for long technical PDFs and LaTeX-heavy reading.

```bash
zathura report.pdf
zathura -P 42 report.pdf
zathura -f indicator report.pdf
```

### `mupdf`

- Use `mupdf` for lightweight viewing and `mutool` when you want scriptable inspection or rendering.
- Good fit when you need a small viewer plus low-level utilities in one package.

```bash
mupdf report.pdf
mutool info report.pdf
mutool draw -o page-%03d.png report.pdf 1-3
```

## Inspect And Extract

### `poppler-utils`

- Best general-purpose shell toolbox for existing PDFs.
- Reach for it first for metadata, text extraction, image extraction, splitting, and merging.

```bash
pdfinfo report.pdf
pdftotext -layout report.pdf -
pdfimages -list report.pdf
pdfunite part1.pdf part2.pdf merged.pdf
```

### `qpdf`

- Use it for structural work: validation, linearization, encryption, decryption, and page-level rewrites.
- Better fit than `poppler-utils` when the goal is to preserve or rewrite PDF structure rather than render content.

```bash
qpdf --check report.pdf
qpdf --linearize in.pdf out.pdf
qpdf --split-pages in.pdf page-%d.pdf
```

### `pymupdf`

- Use it for layout-aware extraction, embedded-object inspection, and automation that may later graduate into Python code.
- The `pymupdf` CLI is available directly; Python imports require an interpreter environment that includes the package.

```bash
pymupdf show -metadata report.pdf
pymupdf gettext -mode layout report.pdf
pymupdf extract report.pdf
```

## OCR And Searchable Output

### `ocrmypdf`

- Best for scanned PDFs that need a text layer while preserving the original page image.
- Prefer this over raw `tesseract` when the input is already a PDF.

```bash
ocrmypdf scan.pdf searchable.pdf
ocrmypdf --deskew --rotate-pages scan.pdf searchable.pdf
ocrmypdf --skip-text --sidecar scan.txt scan.pdf searchable.pdf
```

### `tesseract`

- Use it for image-first OCR, layout experiments, and raw OCR artifacts like hOCR, TSV, ALTO, or searchable PDF.
- Better fit than `ocrmypdf` when the input is a cropped image or when you want direct OCR output formats.

```bash
tesseract receipt.png stdout
tesseract receipt.png receipt pdf
tesseract receipt.png stdout --psm 6 -l eng
```

## Generate PDFs From Other Sources

### `pandoc`

- Use it when the source is Markdown, HTML, or citation-heavy prose and you want a produced PDF at the end.
- It is an authoring and conversion tool, not a tool for editing an existing PDF in place.

```bash
pandoc notes.md -o notes.pdf
pandoc paper.md --citeproc --bibliography refs.bib -o paper.pdf
pandoc report.md --pdf-engine=xelatex -o report.pdf
```

## Practical Defaults

- Existing PDF, shell-first inspection: start with `poppler-utils`.
- Existing PDF, structural rewrite or validation: use `qpdf`.
- Existing PDF, lightweight render or extraction: use `mutool`.
- Existing PDF, layout-aware CLI extraction or scripted parsing: use `pymupdf`.
- Scanned PDF: use `ocrmypdf`.
- Image OCR or OCR debugging: use `tesseract`.
- Full-featured GUI review: use `okular`.
- Keyboard-centric reading: use `zathura`.
