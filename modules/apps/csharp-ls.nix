/*
  Package: csharp-ls
  Description: C# language server implementing LSP on top of Roslyn.
  Homepage: https://github.com/razzmatazz/csharp-language-server
  Documentation: https://github.com/razzmatazz/csharp-language-server#readme
  Repository: https://github.com/razzmatazz/csharp-language-server

  Summary:
    * Provides completions, diagnostics, go-to-definition, and find-references for C# projects.
    * Uses Roslyn's workspace APIs and requires a .NET SDK on PATH.

  Example Usage:
    * `csharp-ls` -- Start the language server (normally launched by the editor).
*/
_:
let
  CsharpLsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."csharp-ls".extended;
    in
    {
      options.programs."csharp-ls".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable csharp-ls.";
        };

        package = lib.mkPackageOption pkgs "csharp-ls" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."csharp-ls" = CsharpLsModule;
}
