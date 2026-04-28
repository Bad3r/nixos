/*
  Package: kotlin-language-server
  Description: Kotlin language server implementing LSP on top of the Kotlin compiler.
  Homepage: https://github.com/fwcd/kotlin-language-server
  Documentation: https://github.com/fwcd/kotlin-language-server/blob/main/README.md
  Repository: https://github.com/fwcd/kotlin-language-server

  Summary:
    * Provides completions, diagnostics, go-to-definition, and find-references for Kotlin projects.
    * Requires a JDK on PATH; the binary is `kotlin-language-server`.

  Example Usage:
    * `kotlin-language-server` -- Start the language server (normally launched by the editor).
*/
_:
let
  KotlinLanguageServerModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."kotlin-language-server".extended;
    in
    {
      options.programs."kotlin-language-server".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable kotlin-language-server.";
        };

        package = lib.mkPackageOption pkgs "kotlin-language-server" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."kotlin-language-server" = KotlinLanguageServerModule;
}
