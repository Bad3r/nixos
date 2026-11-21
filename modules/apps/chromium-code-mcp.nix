/*
  Package: chromium-code-mcp
  Description: MCP server for Chromium code search, Gerrit, LUCI, and the issue tracker.
  Homepage: https://github.com/dgavrilov/chromium-code-mcp
  Documentation: https://github.com/dgavrilov/chromium-code-mcp#readme
  Repository: https://github.com/dgavrilov/chromium-code-mcp

  Summary:
    * Serves Chromium code search, file and folder reads, OWNERS lookups, and commit search over stdio.
    * Reads Gerrit CLs, LUCI try-bot results, build errors, and issues.chromium.org bugs.

  Options:
    CHROMIUM_SEARCH_API_KEY: Replace the public code search API key the server ships with.

  Notes:
    * Sends no telemetry; every request goes to a Chromium, Google, or GitHub (V8 files) host.
    * Registered as the chromium-code-mcp entry of the agent MCP catalog.
*/
_:
let
  ChromiumCodeMcpModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."chromium-code-mcp".extended;
    in
    {
      options.programs.chromium-code-mcp.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable chromium-code-mcp.";
        };

        package = lib.mkPackageOption pkgs "chromium-code-mcp" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.chromium-code-mcp = ChromiumCodeMcpModule;
}
