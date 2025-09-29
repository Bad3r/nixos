/*
  Package: pyright
  Description: Fast type checker for modern Python, powered by Microsoft’s static analyzer.
  Homepage: https://github.com/microsoft/pyright
  Documentation: https://microsoft.github.io/pyright/
  Repository: https://github.com/microsoft/pyright

  Summary:
    * Performs static type checking for Python projects with optional typing hints and gradual typing.
    * Integrates with editors and CI workflows via a single CLI, enabling rapid feedback on type errors.

  Options:
    pyright: Run a full type check using the nearest `pyproject.toml` or `pyrightconfig.json`.
    pyright --watch: Start pyright in watch mode to re-type-check on file changes.
    pyright --outputjson: Emit machine-readable diagnostics for tooling integrations.

  Example Usage:
    * `pyright` — Type-check the current project root.
    * `pyright src --lib` — Analyze the `src` directory including standard library shims.
    * `pyright --watch` — Continuously type-check while developing.
*/

{
  flake.nixosModules.apps.pyright =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.pyright ];
    };

}
