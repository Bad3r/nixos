/*
  Package: python3
  Description: Default CPython 3 interpreter and standard library.
  Homepage: https://www.python.org/
  Documentation: https://docs.python.org/3/
  Repository: https://github.com/python/cpython

  Summary:
    * Provides the default Python interpreter with `pip`, `venv`, and a batteries-included standard library for scripting, web services, and data science.
    * Tracks the default `python3` from the pinned nixpkgs, so the interpreter version follows nixpkgs instead of a hardcoded release.

  Options:
    python3 <script.py>: Execute Python scripts.
    python3 -m <module>: Run library modules as scripts (e.g. `python -m http.server`).
    python3 -m venv <envdir>: Create virtual environments for dependency isolation.
    pip install <pkg>: Install packages into the active environment.

  Example Usage:
    * `python3` -- Launch the interactive REPL.
    * `python3 -m venv .venv && source .venv/bin/activate` -- Create and activate a virtual environment.
    * `python3 -m pip install requests` -- Install packages using pip within the environment.
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
        # hiPrio so the clean python3 interpreter wins over jupyter-all's
        # bundled python3 in system-path (avoids buildEnv subpath collisions).
        environment.systemPackages = [ (lib.hiPrio cfg.package) ];
      };
    };
in
{
  flake.nixosModules.apps.python = PythonModule;
}
