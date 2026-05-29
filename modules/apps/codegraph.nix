/*
  Package: codegraph
  Description: Semantic code intelligence for AI coding agents.
  Homepage: https://github.com/colbymchenry/codegraph
  Documentation: https://colbymchenry.github.io/codegraph/
  Repository: https://github.com/colbymchenry/codegraph

  Summary:
    * Builds a local knowledge graph with symbols, call graphs, and code structure for repository-aware agent queries.
    * Runs as an MCP server and can install agent integration for supported coding assistants.

  Options:
    init: Initialize CodeGraph in a project directory.
    index: Index all files in the project.
    sync: Sync changes since the last index.
    status: Show index status and statistics.
    query: Search for symbols in the codebase.
    context: Build task context and output markdown.
    serve: Start CodeGraph as an MCP server for AI assistants.
    callers: Find functions or methods that call a symbol.
    callees: Find functions or methods called by a symbol.
    impact: Analyze code affected by changing a symbol.
    affected: Find test files affected by changed source files.
    install: Install the CodeGraph MCP server into supported agents.
    uninstall: Remove CodeGraph from supported agents.

  Notes:
    * Package sourced from llm-agents.nix flake (github:Bad3r/llm-agents.nix).
*/
{ inputs, ... }:
{
  flake.nixosModules.apps.codegraph =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.codegraph.extended;
    in
    {
      options.programs.codegraph.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable codegraph.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codegraph;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.codegraph";
          description = "The codegraph package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
}
