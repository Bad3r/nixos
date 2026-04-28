/*
  Package: typescript-language-server
  Description: TypeScript/JavaScript language server wrapping tsserver via LSP.
  Homepage: https://github.com/typescript-language-server/typescript-language-server
  Documentation: https://github.com/typescript-language-server/typescript-language-server#readme
  Repository: https://github.com/typescript-language-server/typescript-language-server

  Summary:
    * Provides completions, diagnostics, go-to-definition, and refactoring for TypeScript and JavaScript projects.
    * Delegates analysis to tsserver and exposes the results over LSP; the binary is `typescript-language-server`.

  Example Usage:
    * `typescript-language-server --stdio` -- Start the language server in stdio mode (normally launched by the editor).
*/
_:
let
  TypescriptLanguageServerModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."typescript-language-server".extended;
    in
    {
      options.programs."typescript-language-server".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable typescript-language-server.";
        };

        package = lib.mkPackageOption pkgs "typescript-language-server" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."typescript-language-server" = TypescriptLanguageServerModule;
}
