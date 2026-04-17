/*
  Package: libreoffice
  Description: Comprehensive, professional-quality productivity suite, a variant of openoffice.org.
  Homepage: https://libreoffice.org/
  Documentation: https://help.libreoffice.org/latest/en-US/text/shared/guide/start_parameters.html
  Repository: https://git.libreoffice.org/core

  Summary:
    * Provides Writer, Calc, Impress, Draw, Base, and Math in a single desktop office suite with OpenDocument support and broad Microsoft Office interoperability.
    * Supports document conversion, scripting, templates, extensions, and local or remote file workflows from the same package.

  Options:
    --writer <file>: Open a document directly in Writer.
    --calc <file>: Open a spreadsheet directly in Calc.
    --impress <file>: Open a presentation directly in Impress.
    --convert-to <format> <file>: Convert office documents in headless or batch workflows.
*/
_:
let
  LibreofficeModule =
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
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable libreoffice.";
        };

        package = lib.mkPackageOption pkgs "libreoffice" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.libreoffice = LibreofficeModule;
}
