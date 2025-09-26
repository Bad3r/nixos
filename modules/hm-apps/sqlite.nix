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
    sqlite3 <database>: Open the interactive shell on a database file or `:memory:` store.
    sqlite3 -cmd "PRAGMA foreign_keys = ON;": Execute statements before entering interactive mode.
    sqlite3 -batch <database> <script.sql>: Run SQL non-interactively and exit on errors.
    sqlite3 -readonly <database>: Open the database in read-only mode to prevent writes.
    sqlite3 .dump <database>: Export the entire database schema and data as SQL text.

  Example Usage:
    * `sqlite3 todo.db "CREATE TABLE IF NOT EXISTS tasks(id INTEGER PRIMARY KEY, title TEXT);"` — Run schema migrations inline.
    * `sqlite3 todo.db ".mode box" ".headers on" "SELECT * FROM tasks;"` — Inspect table data using the shell’s pretty printer.
    * `sqlite3 todo.db ".backup ./backups/todo.db"` — Produce a consistent snapshot of a live database.
*/

{
  flake.homeManagerModules.apps.sqlite =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.sqlite ];
    };
}
