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
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.tesseract.extended;
  TesseractModule = {
    options.programs.tesseract.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable tesseract OCR engine.";
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
