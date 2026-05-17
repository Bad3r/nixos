/*
  Package: nixd
  Description: Feature-rich Nix language server with option and package completion.
  Homepage: https://github.com/nix-community/nixd
  Documentation: https://github.com/nix-community/nixd#readme
  Repository: https://github.com/nix-community/nixd

  Summary:
    * Provides Language Server Protocol (LSP) features for Nix, including diagnostics, hover info, and navigation.
    * Integrates with Nix evaluation to expose nixpkgs package and option-system completions.

  Options:
    nixd: Start the language server for editor integrations.
    --help: Display all available server flags and usage information.
*/
_:
let
  NixdModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.nixd.extended;
    in
    {
      options.programs.nixd.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nixd.";
        };

        package = lib.mkPackageOption pkgs "nixd" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nixd = NixdModule;
}
