/*
  Package: wpsoffice
  Description: Office suite with Writer, Spreadsheet, Presentation, and PDF tools.
  Homepage: https://www.wps.com/
  Documentation: https://help.wps.com/

  Summary:
    * Bundles Writer, Spreadsheet, Presentation, and PDF workflows with Microsoft Office-compatible document handling.
    * Provides a tabbed desktop suite for local editing, templates, and cloud-connected office tasks.

  Options:
    Writer: Use WPS Writer for word-processing documents and templates.
    Spreadsheet: Use the spreadsheet editor for tables, formulas, and chart-based workbooks.
    Presentation: Use the presentation editor for slide decks and presenter workflows.
    PDF: Open the suite's built-in PDF tools alongside office documents.

  Notes:
    * Package is unfree and must remain in `nixpkgs.allowedUnfreePackages`.
*/
_:
let
  WpsofficeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.wpsoffice.extended;
    in
    {
      options.programs.wpsoffice.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable wpsoffice.";
        };

        package = lib.mkPackageOption pkgs "wpsoffice" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "wpsoffice" ];
  flake.nixosModules.apps.wpsoffice = WpsofficeModule;
}
