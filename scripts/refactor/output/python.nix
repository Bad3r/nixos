/*
  Package: python313
  Description: CPython 3.13 interpreter and standard library.
  Homepage: https://www.python.org/
  Documentation: https://docs.python.org/3.13/
  Repository: https://github.com/python/cpython

  Summary:
    * Provides the default Python interpreter with `pip`, `venv`, and a batteries-included standard library for scripting, web services, and data science.
    * Supports zero-cost exceptions, improved f-string diagnostics, and other enhancements introduced in Python 3.13.

  Options:
    python3.13 <script.py>: Execute Python scripts.
    python3.13 -m <module>: Run library modules as scripts (e.g. `python -m http.server`).
    python3.13 -m venv <envdir>: Create virtual environments for dependency isolation.
    pip install <pkg>: Install packages into the active environment.

  Example Usage:
    * `python3.13` — Launch the interactive REPL.
    * `python3.13 -m venv .venv {PRESERVED_DOCUMENTATION}{PRESERVED_DOCUMENTATION} source .venv/bin/activate` — Create and activate a virtual environment.
    * `python3.13 -m pip install requests` — Install packages using pip within the environment.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.python313.extended;
  Python313Module = {
    options.programs.python313.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable python313.";
      };

      package = lib.mkPackageOption pkgs "python313" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.python313 = Python313Module;
}
