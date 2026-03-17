/*
  Package: pymupdf
  Description: Python bindings for MuPDF that extract, render, and modify PDF documents.
  Homepage: https://pymupdf.readthedocs.io/
  Documentation: https://pymupdf.readthedocs.io/en/latest/
  Repository: https://github.com/pymupdf/PyMuPDF

  Summary:
    * Opens PDF and other document formats from Python for text extraction, page rendering, annotations, and structural edits.
    * Exposes a low-level document model suitable for parsers, chunkers, and layout-aware automation.

  Example Usage:
    * `pymupdf show -metadata report.pdf` -- Print high-level PDF metadata from the CLI.
    * `pymupdf gettext -mode layout report.pdf` -- Extract page text with layout-aware spacing.
    * `pymupdf extract report.pdf` -- Extract embedded images, fonts, and attachments.

  Options:
    pymupdf.open(path): Open a document from disk, bytes, or a stream.
    Document.load_page(page_number): Access a specific page for extraction or edits.
    Page.get_text(mode = "text"): Extract plain text, blocks, words, HTML, or structured representations.
    Page.get_pixmap(): Render a page to an image buffer for OCR or previews.

  Notes:
    * The package exposes the `pymupdf` CLI directly; importing the library requires a Python environment that includes the package.
*/
_:
let
  PyMuPdfModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.pymupdf.extended;
    in
    {
      options.programs.pymupdf.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable pymupdf.";
        };

        package = lib.mkPackageOption pkgs [ "python3Packages" "pymupdf" ] { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.pymupdf = PyMuPdfModule;
}
