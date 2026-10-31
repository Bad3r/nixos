/*
  Package: pymupdf
  Description: Python bindings for MuPDF that extract, render, and modify PDF documents.
  Homepage: https://pymupdf.readthedocs.io/
  Documentation: https://pymupdf.readthedocs.io/en/latest/
  Repository: https://github.com/pymupdf/PyMuPDF

  Summary:
    * Opens PDF and other document formats from Python for text extraction, page rendering, annotations, and structural edits.
    * Exposes a low-level document model suitable for parsers, chunkers, and layout-aware automation.

  Notes:
    * Importing the library needs a Python environment that includes pymupdf.
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
