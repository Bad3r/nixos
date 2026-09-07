/*
  Package: xlsx2csv
  Description: Convert xlsx workbooks to CSV from the command line, including very large files.
  Homepage: nil
  Documentation: nil
  Repository: https://github.com/dilshod/xlsx2csv

  Summary:
    * Streams sheets straight out of the xlsx container on the system Python, so large workbooks convert without opening a spreadsheet application.
    * Selects a sheet by number or name, exports every sheet into one stream or one file each, and controls delimiter, quoting, and date, time, and float formats.
    * Reads the workbook from a path or from standard input with '-'.

  Options:
    -s SHEETID: Sheet number to convert; 0 converts every sheet into one stream. Without it only the first sheet is converted.
    -n SHEETNAME: Sheet name to convert.
    -a: Export all sheets; with a directory as the output argument, write one CSV per sheet.
    -p SHEETDELIMITER: Line written between sheets in a multi-sheet stream; pass '' for none (default '--------').
    -I PATTERN: Only include sheets whose names match the pattern; applies with -a.
    -E PATTERN: Exclude sheets whose names match the pattern; applies with -a.
    --exclude_hidden_sheets: Skip hidden sheets; applies with -a.
    -d DELIMITER: Column delimiter, with 'tab' or 'x09' for a tab (default comma).
    -q QUOTING: Field quoting: none, minimal, nonnumeric, or all (default minimal).
    -f DATEFORMAT: Override the date/time output format, for example %Y/%m/%d.
    -t TIMEFORMAT: Override the time output format, for example %H/%M/%S.
    --floatformat FLOATFORMAT: Override the float output format, for example %.15f.
    -i: Skip empty lines.
    --skipemptycolumns: Drop trailing empty columns.
    -m: Merge cells.
    --hyperlinks: Include hyperlinks.
    -c OUTPUTENCODING: Output encoding (default utf-8).
*/
_:
let
  Xlsx2csvModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.xlsx2csv.extended;
    in
    {
      options.programs.xlsx2csv.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable xlsx2csv.";
        };

        package = lib.mkPackageOption pkgs "xlsx2csv" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.xlsx2csv = Xlsx2csvModule;
}
