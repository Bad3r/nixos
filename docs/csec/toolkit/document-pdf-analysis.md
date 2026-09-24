# Pentesting Toolkit: Document & PDF Analysis

[Back to Pentesting Toolkit](../toolkit.md)

## Document & PDF Analysis

- ocrmypdf
  - run..: `ocrmypdf $in.pdf $out.pdf`
  - Repo.: <https://github.com/ocrmypdf/OCRmyPDF>
  - Docs.: <https://ocrmypdf.readthedocs.io/>
  - Desc.: Adds OCR layers to scanned PDFs for searchable evidence.
- poppler-utils
  - run..: `pdftotext $file.pdf -`
  - Repo.: <https://gitlab.freedesktop.org/poppler/poppler>
  - Docs.: <https://poppler.freedesktop.org/>
  - Desc.: pdfinfo, pdfimages, pdftotext for content extraction.
- pymupdf
  - run..: `python -c 'import pymupdf; pymupdf.open("file.pdf")'`
  - Repo.: <https://github.com/pymupdf/PyMuPDF>
  - Docs.: <https://pymupdf.readthedocs.io/>
  - Desc.: Python PDF manipulation library used in analysis scripts.
- qpdf
  - run..: `qpdf --decrypt --password=$pass $in $out`
  - Repo.: <https://github.com/qpdf/qpdf>
  - Docs.: <https://qpdf.readthedocs.io/>
  - Desc.: Structural PDF inspection and decryption.
- tesseract
  - run..: `tesseract $image $out`
  - Repo.: <https://github.com/tesseract-ocr/tesseract>
  - Docs.: <https://tesseract-ocr.github.io/>
  - Desc.: OCR engine behind many image-to-text pipelines.
- vex-tui
  - run..: `vex $file.csv` (`csv-vex-tui` and `xls-vex-tui` are aliases)
  - Repo.: <https://github.com/CodeOne45/vex-tui>
  - Docs.: <https://github.com/CodeOne45/vex-tui#usage>
  - Desc.: Terminal Excel and CSV viewer/editor for triaging tabular evidence exports.
