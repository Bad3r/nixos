/*
  Package: pandoc
  Description: Universal document converter supporting Markdown, LaTeX, HTML, DOCX, PDF, and many more formats.
  Homepage: https://pandoc.org/
  Documentation: https://pandoc.org/MANUAL.html
  Repository: https://github.com/jgm/pandoc

  Summary:
    * Converts documents between numerous markup and word-processing formats, enabling pipelines for publishing, academic writing, and documentation.
    * Supports filters, templates, citations (CSL), cross-references, and embedding of fonts/assets in output formats.

  Options:
    -f <from>, -t <to>: Specify input and output formats (e.g. `-f markdown -t pdf`).
    -o <file>: Write results to a file.
    --citeproc: Enable citation and bibliography processing.
    --filter <program>: Run a JSON filter to transform the AST.
    --template <file>: Use a custom template for final rendering.

  Example Usage:
    * `pandoc README.md -f markdown -t html -o README.html` — Convert Markdown to HTML.
    * `pandoc paper.md --citeproc --bibliography refs.bib -o paper.pdf` — Produce a PDF with citations.
    * `pandoc notes.md -t docx -o notes.docx` — Generate a Word document from Markdown notes.
*/

{
  flake.nixosModules.apps.pandoc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.pandoc ];
    };

}
