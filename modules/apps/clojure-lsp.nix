/*
  Package: clojure-lsp
  Description: Language Server Protocol implementation and CLI automation tool for Clojure projects.
  Homepage: https://clojure-lsp.io/
  Documentation: https://clojure-lsp.io/settings/
  Repository: https://github.com/clojure-lsp/clojure-lsp

  Summary:
    * Offers LSP features (completion, diagnostics, refactors) for editors while also exposing a CLI for formatting, cleaning namespaces, and code analysis.
    * Understands deps.edn, Leiningen, and tools.build projects, sharing analysis with clj-kondo for rich semantic operations.

  Options:
    clean-ns [--dry]: Remove unused requires/imports and sort namespaces in bulk.
    format [--file <path>]: Reformat source files using cljfmt rules with optional file targeting.
    diagnostics [--output '{:format :json}']: Generate project-wide warnings and errors as machine-readable output.
    rename --from ns/sym --to ns/new-sym: Apply safe renames across the codebase.
    listen: Start the language server, communicating over stdio for editor integrations.

  Example Usage:
    * `clojure-lsp clean-ns --dry` — Preview namespace cleanups without modifying files.
    * `clojure-lsp format --filenames src app/core.clj` — Format specific source files.
    * `clojure-lsp listen` — Run the LSP server for editor clients that connect via stdio.
*/

{
  flake.nixosModules.apps."clojure-lsp" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.clojure-lsp ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.clojure-lsp ];
    };
}
