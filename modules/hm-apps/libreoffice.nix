/*
  Package: libreoffice
  Description: Comprehensive, professional-quality productivity suite, a variant of openoffice.org.
  Homepage: https://libreoffice.org/
  Documentation: https://help.libreoffice.org/
  Repository: https://git.libreoffice.org/core

  Summary:
    * Full office suite with Writer, Calc, Impress, Draw, Base, and Math supporting OpenDocument formats and Microsoft Office interoperability.
    * Provides scripting, extension APIs, database connectivity, and integration with LibreOffice Online or remote storage.

  Options:
    --writer <file>: Open directly in Writer with a document.
    --calc <file>: Start Calc spreadsheets or create a new workbook.
    --impress <file>: Open presentations in Impress.
    --convert-to <format> <file>: Convert documents via CLI in batch scripts.

  Example Usage:
    * `libreoffice --writer report.odt` -- Jump straight into editing a Writer document.
    * `libreoffice --calc data.xlsx` -- Analyze spreadsheets with Calc’s pivot tables and functions.
    * `libreoffice --convert-to pdf *.odt` -- Convert multiple documents to PDF on the command line.
*/

{
  flake.homeManagerModules.apps.libreoffice =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.libreoffice.extended;
    in
    {
      options.programs.libreoffice.extended = {
        enable = lib.mkEnableOption "Comprehensive, professional-quality productivity suite, a variant of openoffice.org.";
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.libreoffice ];
      };
    };
}
