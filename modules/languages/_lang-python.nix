/*
  Language: Python
  Description: High-level interpreted language emphasizing code readability and rapid development.
  Homepage: https://www.python.org/
  Documentation: https://docs.python.org/3/
  Repository: https://github.com/python/cpython

  Summary:
    * Provides Python 3 interpreter with modern tooling including uv (fast package installer), pyright (type checker), and ruff (linter/formatter).
    * Supports dynamic typing with optional static type hints, extensive standard library, and rich ecosystem for web, data science, automation, and more.

  Included Tools:
    python3: CPython interpreter with REPL, standard library, and pip package manager.
    uv: Ultra-fast Python package installer and resolver written in Rust, replacing pip/pip-tools workflows.
    pyright: Static type checker providing fast type analysis and IDE integration.
    ruff: Extremely fast Python linter and formatter combining functionality of flake8, black, isort, and more.

  Example Usage:
    * `python -m venv .venv && source .venv/bin/activate` — Create and activate virtual environment.
    * `uv pip install requests` — Install packages with high-performance resolver.
    * `pyright --watch` — Run type checker in watch mode for continuous feedback.
    * `ruff check --fix .` — Lint and auto-fix code issues across project.
*/
_:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.languages.python.extended;
in
{
  options.languages.python.extended = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc ''
        Whether to enable Python language support.

        Enables Python 3 with modern tooling including uv (fast package installer),
        pyright (type checker), and ruff (linter/formatter).

        Example configuration:
        ```nix
        languages.python.extended = {
          enable = true;
          packages.python = pkgs.python312;  # Use Python 3.12
        };
        ```
      '';
    };

    packages = {
      python = lib.mkPackageOption pkgs "python3" {
        example = lib.literalExpression "pkgs.python312";
      };
      uv = lib.mkPackageOption pkgs "uv" {
        example = lib.literalExpression "pkgs.uv";
      };
      pyright = lib.mkPackageOption pkgs "pyright" {
        example = lib.literalExpression "pkgs.pyright";
      };
      ruff = lib.mkPackageOption pkgs "ruff" {
        example = lib.literalExpression "pkgs.ruff";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    programs = {
      python.extended = {
        enable = lib.mkOverride 1000 true;
        package = cfg.packages.python;
      };
      uv.extended = {
        enable = lib.mkOverride 1000 true;
        package = cfg.packages.uv;
      };
      pyright.extended = {
        enable = lib.mkOverride 1000 true;
        package = cfg.packages.pyright;
      };
      ruff.extended = {
        enable = lib.mkOverride 1000 true;
        package = cfg.packages.ruff;
      };
    };
  };
}
