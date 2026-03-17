/*
  Package: ocrmypdf
  Description: Adds an OCR text layer to scanned PDF files, allowing them to be searched.
  Homepage: https://ocrmypdf.readthedocs.io/
  Documentation: https://ocrmypdf.readthedocs.io/en/latest/
  Repository: https://github.com/ocrmypdf/OCRmyPDF

  Summary:
    * Converts scanned PDFs into searchable PDFs by running OCR and embedding a text layer while preserving the original page image.
    * Can deskew, rotate, clean, and optimize pages during OCR to improve downstream extraction quality.

  Example Usage:
    * `ocrmypdf scan.pdf searchable.pdf` -- Add a searchable text layer to a scanned PDF.
    * `ocrmypdf --deskew --rotate-pages scan.pdf searchable.pdf` -- Correct skew and rotation before OCR.
    * `ocrmypdf --skip-text --sidecar scan.txt scan.pdf searchable.pdf` -- OCR only image-only pages and save extracted text to a sidecar file.

  Options:
    --deskew: Straighten scanned pages before OCR.
    --rotate-pages: Detect and fix page rotation automatically.
    --skip-text: Leave pages with an existing text layer untouched.
    --redo-ocr: Remove an existing OCR layer and regenerate it.
    --sidecar <file>: Write recognized text to a separate plain-text file.
*/
_:
let
  OcrMyPdfModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.ocrmypdf.extended;
    in
    {
      options.programs.ocrmypdf.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable ocrmypdf.";
        };

        package = lib.mkPackageOption pkgs "ocrmypdf" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.ocrmypdf = OcrMyPdfModule;
}
