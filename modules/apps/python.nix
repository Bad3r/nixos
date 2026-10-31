/*
  Package: python
  Description: Default CPython 3 interpreter and standard library.
  Homepage: https://www.python.org/
  Documentation: https://docs.python.org/3/
  Repository: https://github.com/python/cpython

  Summary:
    * Provides the default Python interpreter with `venv` and a batteries-included standard library for scripting, web services, and data science.

  Options:
    python3 -m <module>: Run library modules as scripts (e.g. `python -m http.server`).
    python3 -m venv <envdir>: Create virtual environments for dependency isolation.
*/
_:
let
  PythonModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.python.extended;
    in
    {
      options.programs.python.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the default CPython 3 interpreter.";
        };

        package = lib.mkPackageOption pkgs "python3" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.python = PythonModule;
}
