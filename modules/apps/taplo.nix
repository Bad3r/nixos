/*
  Package: taplo
  Description: TOML toolkit written in Rust.
  Homepage: https://taplo.tamasfe.dev
  Documentation: https://taplo.tamasfe.dev/configuration/formatter-options.html
  Repository: https://github.com/tamasfe/taplo

  Summary:
    * Formats and lints TOML documents.
    * Provides language-server, configuration, value extraction, and completion commands.

  Options:
    config: Operate on Taplo configuration files.
    format: Format TOML documents.
    get: Extract values from TOML documents.
    lint: Lint TOML documents.
    lsp: Run language-server operations.
*/
_:
let
  TaploModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.taplo.extended;
    in
    {
      options.programs.taplo.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable taplo.";
        };

        package = lib.mkPackageOption pkgs "taplo" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.taplo = TaploModule;
}
