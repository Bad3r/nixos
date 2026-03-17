/*
  Package: qpdf
  Description: C++ library and CLI utilities for inspecting and manipulating PDF structure.
  Homepage: https://qpdf.sourceforge.io/
  Documentation: https://qpdf.readthedocs.io/en/stable/
  Repository: https://github.com/qpdf/qpdf

  Summary:
    * Rewrites, splits, merges, encrypts, decrypts, and linearizes PDFs while preserving low-level object fidelity.
    * Emits structural JSON and validation output that is useful for parsers, repair flows, and security review.

  Example Usage:
    * `qpdf --check report.pdf` -- Validate PDF structure and cross-reference consistency.
    * `qpdf --linearize in.pdf out.pdf` -- Rewrite a PDF for faster incremental web delivery.
    * `qpdf --split-pages in.pdf page-%d.pdf` -- Write each page to a separate PDF file.

  Options:
    --check: Validate PDF structure and report syntax or cross-reference issues.
    --decrypt: Remove encryption from a PDF when the password is supplied.
    --encrypt: Apply owner or user passwords and permission flags to an output PDF.
    --json: Emit machine-readable document structure and metadata.
    --split-pages: Write each page to a separate PDF file.
*/
_:
let
  QpdfModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.qpdf.extended;
    in
    {
      options.programs.qpdf.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable qpdf.";
        };

        package = lib.mkPackageOption pkgs "qpdf" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.qpdf = QpdfModule;
}
