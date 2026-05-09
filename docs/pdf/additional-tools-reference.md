# PDF Tooling Reference

Reference catalog of PDF tools that complement the active toolkit in [`toolkit.md`](toolkit.md).\
Most can be invoked ad-hoc through `nix run`, dropped into a `nix shell`, or run via `uvx` for PyPI-only packages.\
Promotion to a host happens by authoring a `modules/apps/<name>.nix` module and flipping the corresponding flag in `apps-enable.nix`.

Each entry lists a representative invocation, optional additional invocations, upstream repository, official documentation, a one-line description, a one-line decision hint, and an upstream maintenance classification. Verified against `nixpkgs` rev pinned in `flake.lock` on 2026-05-09.

`Stat.` classifies upstream health as of 2026-05-09: **Maintained** (release on/after 2025-01-01), **Maintenance mode** (mature/stable; active commits but no recent tagged release), **Core utility** (foundational tooling whose release cadence does not map to the other categories), or **Deprecated** (archived, abandoned, or superseded).

## Convert To Markdown Or Structured Output

- docling
  - run..: `nix run nixpkgs#docling -- report.pdf`
  - More..:
    - md: `nix run nixpkgs#docling -- report.pdf --to md --output ./out`
    - formula: `nix run nixpkgs#docling -- --pipeline standard --enrich-formula report.pdf`
    - batch: `nix run nixpkgs#docling -- ./inputs --output ./out`
  - Repo.: <https://github.com/docling-project/docling>
  - Docs.: <https://docling-project.github.io/docling/>
  - Desc.: Layout-aware conversion of PDFs and other office formats (DOCX, PPTX, HTML, images) into Markdown, JSON, or chunks for RAG and LLM pipelines.
  - Use..: Mixed-format inputs or when an explicit document model with sections, tables, and figures must be preserved; prefer over `marker` for non-PDF sources.
  - Stat.: Maintained (v2.93.0, 2026-05-07).
- marker
  - run..: `uvx --from marker-pdf marker_single report.pdf --output_dir out/`
  - More..:
    - batch: `uvx --from marker-pdf marker /path/to/pdfs --output_dir out/ --workers 4`
    - json: `uvx --from marker-pdf marker_single report.pdf --output_format json`
    - html: `uvx --from marker-pdf marker_single report.pdf --output_format html`
  - Repo.: <https://github.com/datalab-to/marker>
  - Docs.: <https://github.com/datalab-to/marker#readme>
  - Desc.: ML-driven PDF-to-Markdown/JSON/HTML converter with strong fidelity on tables, equations, and multi-column layouts. Distributed as the `marker-pdf` PyPI package; not the unrelated `marker` GTK Markdown editor in nixpkgs.
  - Use..: PDF-only batches ahead of RAG ingestion; prefer over `pandoc` when the source is a PDF rather than Markdown.
  - Stat.: Maintained (v1.10.2, 2026-01-31).
- pymupdf4llm
  - run..: `uv run --with pymupdf4llm python -c 'import pymupdf4llm; print(pymupdf4llm.to_markdown("report.pdf"))'`
  - More..:
    - chunks: `uv run --with pymupdf4llm python -c 'import pymupdf4llm; print(pymupdf4llm.to_markdown("report.pdf", page_chunks=True))'`
    - llama: `uv run --with pymupdf4llm --with llama-index python -c 'import pymupdf4llm; pymupdf4llm.LlamaMarkdownReader().load_data("report.pdf")'`
  - Repo.: <https://github.com/pymupdf/RAG>
  - Docs.: <https://pymupdf.readthedocs.io/en/latest/pymupdf4llm/>
  - Desc.: Fast PDF-to-Markdown extraction built on `pymupdf` with helpers for LLaMA Index, LangChain, and page-level chunking. Python-only; no native CLI.
  - Use..: Quick layout-aware Markdown for RAG pipelines without bundled ML models; prefer over `marker` or `docling` when ML model downloads are not desired.
  - Stat.: Maintained (v0.3.4, 2026-02-14).
