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
    * `python3.13 -m venv .venv && source .venv/bin/activate` — Create and activate a virtual environment.
    * `python3.13 -m pip install requests` — Install packages using pip within the environment.
*/

{
  flake.nixosModules.apps.python =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.python313 ];
    };

}
