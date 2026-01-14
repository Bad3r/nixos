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

_:
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
          description = "Whether to enable the formatting tool bundle.";
        };

        packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = with pkgs; [
            biome
            nixfmt
            prettier
            shellcheck
            shfmt
            stylua
            taplo
            treefmt
          ];
          description = ''
            Code formatters and linters for the development environment.

            Included formatters:
            - biome: JavaScript/TypeScript/JSON
            - nixfmt: Nix (RFC 166)
            - prettier: Multi-language formatter (JS/TS/JSON/YAML/MD/HTML/CSS)
            - shellcheck: Shell script linter
            - shfmt: Shell script formatter
            - stylua: Lua formatter
            - taplo: TOML formatter
            - treefmt: Format orchestrator
          '';
          example = lib.literalExpression "with pkgs; [ nixfmt shfmt ]";
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
