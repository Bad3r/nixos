{ config, lib, ... }:
let
  mcp = config.flake.lib.agents.mcp;
in
{
  flake.nixosModules.hosts-common.imports = [
    (
      { config, ... }:
      {
        # The firefox MCP server's wrapper runs the driver from this app.
        config.programs.geckodriver.extended.enable = lib.mkIf (lib.elem "firefox" (
          lib.concatMap (client: mcp.clients.${client}.enabledNames config) mcp.servers.firefox.clients
        )) (lib.mkOverride 1050 true);
      }
    )
  ];
}
