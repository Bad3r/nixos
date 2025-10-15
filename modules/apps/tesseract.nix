/*
  Package: tesseract
  Description: Open-source OCR engine supporting 100+ languages with script detection.
  Homepage: https://github.com/tesseract-ocr/tesseract
  Documentation: https://tesseract-ocr.github.io/tessdoc/

  Summary:
    * Installs the `tesseract` CLI for converting images and PDFs into searchable text.
    * Supports automated layout detection, hOCR/ALTO output, and custom training data.
    * Works with companion utilities such as `tesseract-lang` packages to add language models.
*/

{
  flake.nixosModules.apps.tesseract =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        tesseract
      ];
    };
}
