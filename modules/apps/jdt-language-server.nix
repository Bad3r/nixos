/*
  Package: jdt-language-server
  Description: Eclipse JDT-based Java language server implementing LSP.
  Homepage: https://github.com/eclipse-jdtls/eclipse.jdt.ls
  Documentation: https://github.com/eclipse-jdtls/eclipse.jdt.ls/wiki
  Repository: https://github.com/eclipse-jdtls/eclipse.jdt.ls

  Summary:
    * Delivers Java completions, diagnostics, go-to-definition, and refactoring powered by Eclipse JDT.
    * Requires a JDK on PATH; the binary is `jdtls`.

  Example Usage:
    * `jdtls` -- Start the Java language server (normally launched by the editor).
*/
_:
let
  JdtLanguageServerModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."jdt-language-server".extended;
    in
    {
      options.programs."jdt-language-server".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable jdt-language-server.";
        };

        package = lib.mkPackageOption pkgs "jdt-language-server" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."jdt-language-server" = JdtLanguageServerModule;
}
