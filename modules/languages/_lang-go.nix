/*
  Language: Go
  Description: Statically typed compiled language designed for simplicity, concurrency, and fast compilation.
  Homepage: https://go.dev/
  Documentation: https://go.dev/doc/
  Repository: https://github.com/golang/go

  Summary:
    * Provides Go compiler and toolchain with language server (gopls), comprehensive linter (golangci-lint), and debugger (delve).
    * Emphasizes simplicity and productivity with built-in concurrency primitives (goroutines, channels), fast compilation, and single-binary deployment.

  Included Tools:
    go: Go compiler and toolchain with built-in commands for build, test, format, and module management.
    gopls: Official Go language server providing IDE features including completion, navigation, and refactoring.
    golangci-lint: Fast linter aggregator running multiple linters in parallel with unified configuration.
    delve: Full-featured debugger for Go programs with support for goroutines and expression evaluation.

  Example Usage:
    * `go mod init example.com/myproject` — Initialize new Go module.
    * `go build -o myapp .` — Build binary from current module.
    * `golangci-lint run --enable-all` — Run comprehensive linting with all available checkers.
    * `dlv debug` — Start interactive debugging session for current package.
*/
_:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.languages.go.extended;
in
{
  options.languages.go.extended = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc ''
        Whether to enable Go language support.

        Enables the Go toolchain with language server (gopls), linter (golangci-lint),
        and debugger (delve).

        Example configuration:
        ```nix
        languages.go.extended = {
          enable = true;
          packages.go = pkgs.go_1_22;  # Use Go 1.22
        };
        ```
      '';
    };

    packages = {
      go = lib.mkPackageOption pkgs "go" {
        example = lib.literalExpression "pkgs.go_1_22";
      };
      gopls = lib.mkPackageOption pkgs "gopls" {
        example = lib.literalExpression "pkgs.gopls";
      };
      "golangci-lint" = lib.mkPackageOption pkgs "golangci-lint" {
        example = lib.literalExpression "pkgs.golangci-lint";
      };
      delve = lib.mkPackageOption pkgs "delve" {
        example = lib.literalExpression "pkgs.delve";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    programs = {
      go.extended = {
        enable = lib.mkOverride 1000 true;
        package = cfg.packages.go;
      };
      gopls.extended = {
        enable = lib.mkOverride 1000 true;
        package = cfg.packages.gopls;
      };
      "golangci-lint".extended = {
        enable = lib.mkOverride 1000 true;
        package = cfg.packages."golangci-lint";
      };
      delve.extended = {
        enable = lib.mkOverride 1000 true;
        package = cfg.packages.delve;
      };
    };
  };
}
