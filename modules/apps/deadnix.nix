/*
  Package: deadnix
  Description: Detects unused let-bindings and function parameters in Nix expressions.
  Homepage: https://github.com/astro/deadnix
  Documentation: https://github.com/astro/deadnix#usage
  Repository: https://github.com/astro/deadnix

  Summary:
    * Analyses Nix code to highlight dead code that can be safely removed.
    * Supports JSON output for integration with editors and CI pipelines.

  Options:
    deadnix <path>: Scan a file or directory for unused bindings.
    deadnix --no-link: Suppress documentation links in the output.
    deadnix --output json: Emit machine-readable reports.

  Example Usage:
    * `deadnix .` -- Report unused definitions across the current project.
    * `deadnix modules --output json` -- Generate JSON diagnostics for editor tooling.
    * `deadnix --no-link flake.nix` -- Produce plain text output without hyperlinks.
*/
_:
let
  DeadnixModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.deadnix.extended;
    in
    {
      options.programs.deadnix.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable deadnix.";
        };

        package = lib.mkPackageOption pkgs "deadnix" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.deadnix = DeadnixModule;
}
