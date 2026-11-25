/*
  Package: mcp-codemode
  Description: Local Code Mode MCP gateway multiplexing stdio and Streamable HTTP servers.
  Homepage: https://github.com/Bad3r/nixos
  Documentation: https://github.com/Bad3r/nixos/blob/main/docs/reference/mcp-tools.md
  Repository: https://github.com/Bad3r/nixos

  Summary:
    * Exposes `search` and `execute` MCP tools to coding agents over stdio, running model-written JS/TS in Bubblewrap + Node 24 permissions.
    * Multiplexes upstream stdio and Streamable HTTP MCP servers with host-side SOPS secret header injection.
    * Supports hot-reloaded project and user overrides in `$XDG_STATE_HOME/mcp-codemode/overrides.json` (`mcp-codemode enable [--user]`) and startup `MCP_CODEMODE_ENABLE` / `MCP_CODEMODE_DISABLE` env toggles.
    * Checks `enable` and `disable` names and identifier aliases against `--manifest`, or else `/etc/mcp-codemode/servers.json` (the registry's `codemode`-routed servers), and stores the listed name. Names go unchecked when `--manifest` is omitted and that file is absent.
*/
{ config, ... }:
let
  inherit (config.flake.lib.agents.mcp) gatewayServerNames;

  McpCodemodeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."mcp-codemode".extended;
    in
    {
      options.programs."mcp-codemode".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the mcp-codemode gateway CLI.";
        };

        package = lib.mkPackageOption pkgs "mcp-codemode" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
        environment.etc."mcp-codemode/servers.json".text = builtins.toJSON gatewayServerNames;
      };
    };
in
{
  flake.nixosModules.apps."mcp-codemode" = McpCodemodeModule;

  perSystem =
    { pkgs, ... }:
    {
      checks."apps/mcp-codemode" =
        pkgs.runCommand "mcp-codemode-check"
          {
            passthru.runtimeCheck = true;
            package = pkgs.callPackage ../../packages/mcp-codemode { };
          }
          ''
            test -x "$package/bin/mcp-codemode"
            touch "$out"
          '';
    };
}
