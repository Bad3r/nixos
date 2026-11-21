{ config, ... }:
let
  firefoxApp = config.flake.lib.agents.mcp.servers.firefox.app;
in
{
  flake.nixosModules.hosts-common.imports = [
    (
      { config, lib, ... }:
      {
        # The firefox MCP server exists where its app's row is on, and its wrapper
        # runs the driver from this app.
        config.programs.geckodriver.extended.enable = lib.mkIf (lib.attrByPath [
          "programs"
          firefoxApp
          "extended"
          "enable"
        ] false config) (lib.mkOverride 1050 true);
      }
    )
  ];
}
