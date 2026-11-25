{ config, lib, ... }:
let
  mcp = config.flake.lib.agents.mcp;
  anyClientEnabled =
    cfg:
    lib.any (app: lib.attrByPath [ "programs" app "extended" "enable" ] false cfg) [
      "antigravity-cli"
      "antigravity-hub"
      "claude-code"
      "codex"
    ];
in
{
  flake.nixosModules.hosts-common.imports = [
    (
      { config, ... }:
      {
        # Every managed agent routes MCP tools through the mcp-codemode gateway.
        config.programs."mcp-codemode".extended.enable = lib.mkIf (anyClientEnabled config) (
          lib.mkOverride 1050 true
        );

        # The firefox MCP server's wrapper runs the driver from this app.
        config.programs.geckodriver.extended.enable = lib.mkIf (lib.elem "firefox" (
          lib.concatMap (client: mcp.clients.${client}.enabledNames config) mcp.servers.firefox.clients
        )) (lib.mkOverride 1050 true);
      }
    )
  ];
}
