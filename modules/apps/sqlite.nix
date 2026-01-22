/*
  Package: sqlite
  Description: Self-contained, serverless, zero-configuration SQL database engine.
  Homepage: https://www.sqlite.org/
  Documentation: https://www.sqlite.org/docs.html
  Repository: https://github.com/sqlite/sqlite

  Summary:
    * Provides the sqlite3 CLI for embedding SQL workloads in scripts and local applications without managing a database server.
    * Supports ACID transactions, virtual tables, FTS5 full-text search, JSON functions, and an interactive shell for data exploration.

  Options:
    -cmd <statement>: Execute SQL statement before entering interactive mode.
    -batch: Run non-interactively; exit on errors.
    -readonly: Open the database in read-only mode to prevent writes.
    -line: Format query results as single-line records for easier parsing.
    -json: Output results as JSON arrays.
    -box: Display results in a bordered box format.
*/
_:
let
  SqliteModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.sqlite.extended;
    in
    {
      options.programs.sqlite.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable sqlite.";
        };

        package = lib.mkPackageOption pkgs "sqlite" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.sqlite = SqliteModule;
}
