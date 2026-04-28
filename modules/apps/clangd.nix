/*
  Package: clangd
  Description: C/C++ language server built on LLVM's Clang, providing IDE features via LSP.
  Homepage: https://clangd.llvm.org/
  Documentation: https://clangd.llvm.org/installation
  Repository: https://github.com/llvm/llvm-project/tree/main/clang-tools-extra/clangd

  Summary:
    * Delivers completions, diagnostics, go-to-definition, and refactoring for C and C++ projects.
    * Ships as part of the `clang-tools` package, which bundles all LLVM/Clang static analysis utilities.

  Example Usage:
    * `clangd --version` -- Print the clangd version.
    * Automatically launched by editors when opening C/C++ files with a compile_commands.json present.
*/
_:
let
  ClangdModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.clangd.extended;
    in
    {
      options.programs.clangd.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable clangd (via clang-tools).";
        };

        package = lib.mkPackageOption pkgs "clang-tools" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.clangd = ClangdModule;
}
