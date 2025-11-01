/*
  Package: statix
  Description: Lints Nix code for common antipatterns and suggests idiomatic rewrites.
  Homepage: https://github.com/nerdypepper/statix
  Documentation: https://github.com/nerdypepper/statix#readme
  Repository: https://github.com/nerdypepper/statix

  Summary:
    * Scans Nix files for issues such as legacy attribute syntax, shadowed bindings, and redundant overrides.
    * Integrates with CI and editor tooling via JSON output or autofix mode.

  Options:
    statix check [path]: Run lint checks and report findings.
    statix fix [path]: Apply safe autofixes directly to the file tree.
    statix --format json check [path]: Emit machine-readable diagnostics for editor integration.

  Example Usage:
    * `statix check .` — Lint all Nix files in the current directory.
    * `statix fix modules/` — Autofix eligible issues inside `modules/`.
    * `statix --format json check flake.nix` — Produce JSON diagnostics for tooling.
*/
_:
let
  StatixModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.statix.extended;
    in
    {
      options.programs.statix.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable statix.";
        };

        package = lib.mkPackageOption pkgs "statix" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.statix = StatixModule;
}
