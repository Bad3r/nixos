/*
  Package: biome
  Description: Toolchain of the web.
  Homepage: https://biomejs.dev/
  Documentation: https://biomejs.dev/reference/cli/
  Repository: https://github.com/biomejs/biome

  Summary:
    * Formats JavaScript, TypeScript, JSON, CSS, and HTML sources.
    * Provides formatter, linter, import sorting, and language-server commands from one binary.

  Options:
    check: Run formatter, linter, and import sorting checks.
    ci: Run checks in CI-oriented mode.
    format: Format supported files.
    lsp-proxy: Start the Language Server Protocol proxy.
*/
_:
let
  BiomeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.biome.extended;
    in
    {
      options.programs.biome.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable biome.";
        };

        package = lib.mkPackageOption pkgs "biome" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.biome = BiomeModule;
}
