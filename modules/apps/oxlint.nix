/*
  Package: oxlint
  Description: High-performance JavaScript and TypeScript linter from the Oxc project.
  Homepage: https://oxc.rs/
  Documentation: https://oxc.rs/docs/guide/usage/linter
  Repository: https://github.com/oxc-project/oxc

  Summary:
    * Lints JavaScript, TypeScript, JSX, and Vue sources with native ports of ESLint core and plugin rules.
    * Runs ESLint-compatible JavaScript plugins for rules that have no native port.

  Options:
    --fix: Apply safe fixes in place.
    --type-aware: Run type-aware rules through the oxlint-tsgolint package.
    --init: Generate a starter .oxlintrc.json.
    --lsp: Start the language server for editor diagnostics.
*/
_:
let
  OxlintModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.oxlint.extended;
    in
    {
      options.programs.oxlint.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable oxlint.";
        };

        package = lib.mkPackageOption pkgs "oxlint" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.oxlint = OxlintModule;
}
