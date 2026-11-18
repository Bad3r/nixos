/*
  Package: oxfmt
  Description: Prettier-compatible formatter from the Oxc project.
  Homepage: https://oxc.rs/
  Documentation: https://oxc.rs/docs/guide/usage/formatter
  Repository: https://github.com/oxc-project/oxc

  Summary:
    * Formats JavaScript, TypeScript, JSON, CSS, Markdown, YAML, and other web sources.
    * Uses Prettier output as its baseline and reads Prettier-style options.

  Options:
    --check: Report unformatted files without writing.
    --write: Format files in place.
    --init: Generate a starter .oxfmtrc.json.
    --migrate: Convert an existing Prettier or Biome configuration.
    --lsp: Start the language server for editor formatting.
*/
_:
let
  OxfmtModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.oxfmt.extended;
    in
    {
      options.programs.oxfmt.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable oxfmt.";
        };

        package = lib.mkPackageOption pkgs "oxfmt" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.oxfmt = OxfmtModule;
}
