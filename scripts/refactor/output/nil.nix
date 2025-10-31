/*
  Package: nil
  Description: Fast Nix language server offering diagnostics, completions, and formatting.
  Homepage: https://github.com/oxalica/nil
  Documentation: https://github.com/oxalica/nil#readme
  Repository: https://github.com/oxalica/nil

  Summary:
    * Provides Language Server Protocol (LSP) features like hover info, go-to-definition, and code actions for Nix.
    * Integrates with popular editors and includes experimental formatting and eval previews.

  Options:
    --version: Print the language server version shipped in the build.
    --help: Display all available server flags and usage information.
    --stdio: Run the language server over stdio for LSP integrations.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nil.extended;
  NilModule = {
    options.programs.nil.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable nil.";
      };

      package = lib.mkPackageOption pkgs "nil" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.nil = NilModule;
}
