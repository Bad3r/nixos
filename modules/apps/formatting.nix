/*
  Package: formatting
  Description: Collection bundle of common code formatters used across the repository.
  Homepage: https://github.com/Bad3r/nixos
  Documentation: https://github.com/Bad3r/nixos
  Repository: https://github.com/Bad3r/nixos

  Summary:
    * Installs the split formatter providers used by the central treefmt module.
    * Exposes host packages only. Formatter behavior is configured in `modules/development/formatter.nix`.

  Options:
    formatting bundle: Provides formatter binaries; individual tools expose their own flags (see respective man pages).

  Example Usage:
    * `nix fmt` -- Run the configured formatter suite on the working tree.
    * `nix develop` -- Enter the development shell with all formatters available on `$PATH`.
*/

{ config, ... }:
let
  flakeConfig = config;
  FormattingModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.formatting.extended;
    in
    {
      options.programs.formatting.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the formatting tool bundle.";
        };

        packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = flakeConfig.flake.lib.formatting.formatterPackages pkgs;
          description = ''
            Code formatter providers exposed to host environments.

            Included formatters:
            - biome: JavaScript, TypeScript, JSON, JSONC, CSS, and HTML formatter
            - mdformat with mdformat-gfm: Markdown formatter
            - nixfmt: Nix (RFC 166)
            - ruff: Python formatter provider
            - shfmt: Shell script formatter
            - stylua: Lua formatter
            - taplo: TOML formatter
            - yamlfmt: YAML formatter
          '';
          example = lib.literalExpression "config.flake.lib.formatting.formatterPackages pkgs";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = cfg.packages;
      };
    };
in
{
  flake.nixosModules.apps.formatting = FormattingModule;
}
