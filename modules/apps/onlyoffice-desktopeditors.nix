/*
  Package: onlyoffice-desktopeditors
  Description: Desktop office suite with document, spreadsheet, presentation, form, and PDF editors.
  Homepage: https://www.onlyoffice.com/
  Documentation: https://helpcenter.onlyoffice.com/
  Repository: https://github.com/ONLYOFFICE/DesktopEditors

  Summary:
    * Combines text documents, spreadsheets, presentations, fillable forms, PDFs, and diagram viewing in one tabbed desktop suite.
    * Connects to ONLYOFFICE and third-party clouds for collaborative editing while preserving local offline workflows.

  Options:
    Text documents: Use the document editor for formatting, bookmarks, tables of contents, and mail merge.
    Spreadsheets: Use formulas, charts, named ranges, and macros in workbook files.
    Presentations: Build slide decks with presenter mode, objects, and style controls.
    PDF: Edit PDF text, annotate files, and create or fill PDF forms.
*/
_:
let
  OnlyofficeDesktopeditorsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."onlyoffice-desktopeditors".extended;
    in
    {
      options.programs.onlyoffice-desktopeditors.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable onlyoffice-desktopeditors.";
        };

        package = lib.mkPackageOption pkgs "onlyoffice-desktopeditors" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.onlyoffice-desktopeditors = OnlyofficeDesktopeditorsModule;
}
