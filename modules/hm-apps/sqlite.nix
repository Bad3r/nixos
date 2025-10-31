/*
  Package: sqlite
  Description: Self-contained, serverless, zero-configuration SQL database engine.
  Homepage: https://www.sqlite.org/
  Documentation: https://www.sqlite.org/docs.html
  Repository: https://github.com/sqlite/sqlite

  Summary:
    * Ships the `sqlite3` binary for embedding SQL workloads in scripts, local apps, and analysis pipelines without managing a server.
    * Supports ACID transactions, virtual tables, FTS5 search, JSON functions, and an interactive shell for lightweight data exploration.

  Options:
    -cmd "PRAGMA foreign_keys = ON;": Execute statements before entering interactive mode.
    -batch <database> <script.sql>: Run SQL non-interactively and exit on errors.
    -readonly <database>: Open the database in read-only mode to prevent writes.
    -line: Format query results as single-line records for easier parsing.

  Example Usage:
    * `sqlite3 todo.db "CREATE TABLE IF NOT EXISTS tasks(id INTEGER PRIMARY KEY, title TEXT);"` — Run schema migrations inline.
    * `sqlite3 todo.db ".mode box" ".headers on" "SELECT * FROM tasks;"` — Inspect table data using the shell’s pretty printer.
    * `sqlite3 todo.db ".backup ./backups/todo.db"` — Produce a consistent snapshot of a live database.
*/

{
  flake.homeManagerModules.apps.sqlite =
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
        enable = lib.mkEnableOption "Self-contained, serverless, zero-configuration SQL database engine.";
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.sqlite ];
      };
    };
}
