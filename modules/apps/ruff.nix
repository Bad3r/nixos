/*
  Package: ruff
  Description: Extremely fast Python linter, formatter, and import sorter.
  Homepage: https://github.com/astral-sh/ruff
  Documentation: https://docs.astral.sh/ruff/
  Repository: https://github.com/astral-sh/ruff

  Summary:
    * Provides drop-in replacements for tools like Flake8, isort, and autoflake with a single binary.
    * Offers lightning-fast linting, formatting, and refactoring for modern Python projects.

  Options:
    ruff check <path>: Run Ruff's linting rules against files or directories.
    ruff format <path>: Apply Ruff's formatter to Python sources.
    ruff clean: Remove Ruff's cache directory for fresh runs.

  Example Usage:
    * `ruff check src/` -- Lint the `src` package.
    * `ruff format .` -- Format all Python files in the current directory.
    * `ruff check --select I --fix` -- Sort imports and apply fixes automatically.
*/
_:
let
  RuffModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.ruff.extended;
    in
    {
      options.programs.ruff.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable ruff.";
        };

        package = lib.mkPackageOption pkgs "ruff" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.ruff = RuffModule;
}
