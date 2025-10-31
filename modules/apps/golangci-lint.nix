/*
  Package: golangci-lint
  Description: Meta linter for Go aggregating fast linters with shared caching.
  Homepage: https://golangci-lint.run/
  Documentation: https://golangci-lint.run/usage/install/
  Repository: https://github.com/golangci/golangci-lint

  Summary:
    * Bundles dozens of Go linters (vet, staticcheck, revive, and more) under a single command with smart caching.
    * Supports editor integrations and CI workflows to enforce coding standards consistently.

  Example Usage:
    * `golangci-lint run ./...` — Lint all Go packages in the current module using the default configuration.
    * `golangci-lint run --enable govet --disable errcheck` — Toggle specific linters for targeted analysis.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  GolangciLintModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."golangci-lint".extended;
    in
    {
      options.programs.golangci-lint.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable golangci-lint.";
        };

        package = lib.mkPackageOption pkgs "golangci-lint" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.golangci-lint = GolangciLintModule;
}
