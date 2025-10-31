/*
  Package: github-mcp-server
  Description: GitHub Model Context Protocol (MCP) server for exposing repository operations to AI agents.
  Homepage: https://github.com/github/mcp
  Documentation: https://github.com/github/mcp
  Repository: https://github.com/github/mcp

  Summary:
    * Runs a local MCP server that brokers GitHub repository data and tool access for compliant AI clients.
    * Enables agents to inspect issues, pull requests, and workflows through standardized capabilities.

  Options:
    github-mcp-server stdio: Start the server over stdio for embedding in other processes.
    github-mcp-server socket --port <port>: Run the MCP server on a TCP socket.
    github-mcp-server --read-only: Restrict available operations to non-mutating actions.

  Example Usage:
    * `github-mcp-server stdio --toolsets code,issues` — Launch the server with code and issue management tools.
    * `github-mcp-server socket --port 8765` — Expose MCP services over TCP for remote clients.
    * `github-mcp-server stdio --read-only` — Share repository insights without allowing mutations.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.github-mcp-server.extended;
  GithubMcpServerModule = {
    options.programs.github-mcp-server.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable github-mcp-server.";
      };

      package = lib.mkPackageOption pkgs "github-mcp-server" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.github-mcp-server = GithubMcpServerModule;
}
