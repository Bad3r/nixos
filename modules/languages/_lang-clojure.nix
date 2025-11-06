/*
  Language: Clojure
  Description: Dynamic functional language for the JVM emphasizing immutability, simplicity, and interactive development.
  Homepage: https://clojure.org/
  Documentation: https://clojure.org/reference/documentation
  Repository: https://github.com/clojure/clojure

  Summary:
    * Provides complete Clojure ecosystem including CLI tools (clojure), language server (clojure-lsp), build tool (leiningen), and scripting runtime (babashka).
    * Emphasizes REPL-driven development with persistent data structures, first-class functions, and powerful macro system for metaprogramming.

  Included Tools:
    clojure-cli: Official Clojure CLI tools for running programs, managing dependencies, and starting REPLs.
    clojure-lsp: Language server implementation providing IDE features like completion, refactoring, and navigation.
    leiningen: Traditional Clojure build automation tool with project templates, dependency management, and plugin ecosystem.
    babashka: Fast native Clojure interpreter for scripting and command-line tools, enabling instant startup times.

  Example Usage:
    * `clj -M -m myapp.core` — Run Clojure application using deps.edn configuration.
    * `lein repl` — Start REPL with project dependencies loaded for interactive development.
    * `bb script.clj` — Execute Clojure script with near-instant startup via babashka interpreter.
    * `clojure-lsp format` — Format source files according to community style guidelines.
*/
_:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.languages.clojure.extended;
in
{
  options.languages.clojure.extended = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc ''
        Whether to enable Clojure language support.

        Enables the complete Clojure ecosystem including CLI tools, language server,
        build tool (leiningen), and scripting runtime (babashka).

        Example configuration:
        ```nix
        languages.clojure.extended = {
          enable = true;
          packages.babashka = pkgs.babashka-bin;  # Use binary distribution
        };
        ```
      '';
    };

    packages = {
      clojure-cli = lib.mkPackageOption pkgs "clojure" {
        example = lib.literalExpression "pkgs.clojure";
      };
      clojure-lsp = lib.mkPackageOption pkgs "clojure-lsp" {
        example = lib.literalExpression "pkgs.clojure-lsp";
      };
      leiningen = lib.mkPackageOption pkgs "leiningen" {
        example = lib.literalExpression "pkgs.leiningen";
      };
      babashka = lib.mkPackageOption pkgs "babashka" {
        example = lib.literalExpression "pkgs.babashka-bin";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    programs = {
      "clojure-cli".extended = {
        enable = lib.mkOverride 1000 true;
        package = cfg.packages.clojure-cli;
      };
      "clojure-lsp".extended = {
        enable = lib.mkOverride 1000 true;
        package = cfg.packages.clojure-lsp;
      };
      leiningen.extended = {
        enable = lib.mkOverride 1000 true;
        package = cfg.packages.leiningen;
      };
      babashka.extended = {
        enable = lib.mkOverride 1000 true;
        package = cfg.packages.babashka;
      };
    };
  };
}
