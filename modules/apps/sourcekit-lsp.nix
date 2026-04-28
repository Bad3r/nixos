/*
  Package: sourcekit-lsp
  Description: Apple's Swift/C/C++/Objective-C language server implementing LSP.
  Homepage: https://github.com/swiftlang/sourcekit-lsp
  Documentation: https://github.com/swiftlang/sourcekit-lsp/blob/main/README.md
  Repository: https://github.com/swiftlang/sourcekit-lsp

  Summary:
    * Provides completions, diagnostics, go-to-definition, and find-references for Swift projects.
    * Ships as part of the Swift toolchain via `swiftPackages.sourcekit-lsp`.

  Example Usage:
    * `sourcekit-lsp` -- Start the language server (normally launched by the editor).
*/
_:
let
  SourcekitLspModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."sourcekit-lsp".extended;
    in
    {
      options.programs."sourcekit-lsp".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable sourcekit-lsp (via swiftPackages).";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.swiftPackages.sourcekit-lsp;
          defaultText = lib.literalExpression "pkgs.swiftPackages.sourcekit-lsp";
          description = "The sourcekit-lsp package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."sourcekit-lsp" = SourcekitLspModule;
}
