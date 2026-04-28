/*
  Package: lua-language-server
  Description: Lua language server implementing LSP with EmmyLua annotation support.
  Homepage: https://github.com/LuaLS/lua-language-server
  Documentation: https://luals.github.io/
  Repository: https://github.com/LuaLS/lua-language-server

  Summary:
    * Provides completions, diagnostics, go-to-definition, and hover for Lua projects.
    * Supports EmmyLua annotations for gradual typing and improved IDE inference.

  Example Usage:
    * `lua-language-server` -- Start the language server (normally launched by the editor).
*/
_:
let
  LuaLanguageServerModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."lua-language-server".extended;
    in
    {
      options.programs."lua-language-server".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable lua-language-server.";
        };

        package = lib.mkPackageOption pkgs "lua-language-server" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."lua-language-server" = LuaLanguageServerModule;
}
