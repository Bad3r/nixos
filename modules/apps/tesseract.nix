/*
  Package: tesseract
  Description: Open-source OCR engine supporting 100+ languages with script detection.
  Homepage: https://github.com/tesseract-ocr/tesseract
  Documentation: https://tesseract-ocr.github.io/tessdoc/
  Repository: https://github.com/tesseract-ocr/tesseract

  Summary:
    * Installs the `tesseract` CLI for converting images into text, hOCR, TSV, ALTO XML, or searchable PDF output.
    * Supports automated layout detection, multiple page segmentation modes, and custom language models.
    * Works with companion utilities such as `tesseract-lang` packages to add language models.

  Example Usage:
    * `tesseract receipt.png stdout` -- OCR an image and print plain text to standard output.
    * `tesseract receipt.png receipt pdf` -- Generate a searchable PDF from an image input.
    * `tesseract receipt.png stdout --psm 6 -l eng` -- OCR a cropped text block with an explicit page segmentation mode and language.

  Options:
    -l <langs>: Select one or more trained languages, such as `eng` or `eng+ara`.
    --psm <mode>: Control page segmentation behavior for full pages, blocks, lines, or words.
    hocr: Emit hOCR HTML with OCR coordinates and confidence data.
    pdf: Emit searchable PDF output with an invisible text layer.
*/

_:
let
  TesseractModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.tesseract.extended;
    in
    {
      options.programs.tesseract.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable tesseract OCR engine.";
        };

        package = lib.mkPackageOption pkgs "tesseract" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.tesseract = TesseractModule;
}
