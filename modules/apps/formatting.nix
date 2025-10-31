/*
  Package: formatting
  Description: Collection bundle of common code formatters used across the repository.
  Homepage: https://github.com/vx/nixos
  Documentation: https://github.com/vx/nixos
  Repository: https://github.com/vx/nixos

  Summary:
    * Installs the project-standard formatter toolchain (e.g. `nixfmt`, `shfmt`, `prettier`) to ensure consistent styling across languages.
    * Intended for developers entering the repo's `nix develop` environment or running `nix fmt` locally.

  Options:
    formatting bundle: Provides formatter binaries; individual tools expose their own flags (see respective man pages).

  Example Usage:
    * `nix fmt` — Run the configured formatter suite on the working tree.
    * `nix develop` — Enter the development shell with all formatters available on `$PATH`.
*/

{
  config,
  lib,
  pkgs,
  ...
}:
let
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
          description = lib.mdDoc "Whether to enable the formatting tool bundle.";
        };

        packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = with pkgs; [
            biome
            nixfmt-rfc-style
            shellcheck
            prettier
            shfmt
            treefmt
          ];
          description = lib.mdDoc ''
            Code formatters and linters for the development environment.

            Included formatters:
            - biome: JavaScript/TypeScript/JSON
            - nixfmt-rfc-style: Nix (RFC 166)
            - shellcheck: Shell script linter
            - prettier: Multi-language formatter
            - shfmt: Shell script formatter
            - treefmt: Format orchestrator
          '';
          example = lib.literalExpression "with pkgs; [ nixfmt-rfc-style shfmt ]";
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
