/*
  Package: duckdb
  Description: Embeddable SQL OLAP Database Management System.
  Homepage: https://duckdb.org/
  Documentation: https://duckdb.org/docs/stable/clients/cli/overview
  Repository: https://github.com/duckdb/duckdb

  Summary:
    * Provides a standalone CLI for querying transient in-memory and persistent DuckDB databases.
    * Supports analytical SQL workloads, file-backed databases, and data import/export from the terminal.

  Options:
    -c COMMAND: Run COMMAND and exit.
    -csv: Set output mode to CSV.
    -json: Set output mode to JSON.
    -readonly: Open the database read-only.
    -init FILENAME: Run a startup script instead of ~/.duckdbrc.
*/
_:
let
  DuckdbModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.duckdb.extended;
    in
    {
      options.programs.duckdb.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable duckdb.";
        };

        package = lib.mkPackageOption pkgs "duckdb" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.duckdb = DuckdbModule;
}
