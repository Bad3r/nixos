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
    * Claude Code and Codex integration is declarative: the MCP server lives in
      modules/agents/mcp/servers.nix, the agent instructions in
      modules/agents/system-prompt.nix, and the Claude prompt hook and tool
      permission in modules/agents/claude-code/. `codegraph install` edits files
      Home Manager owns; a repository needs only `codegraph init`.
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

      # Defaults reach every entry point, including MCP servers that Codex
      # starts with a filtered environment. Direct mode keeps the daemon socket
      # out of .codegraph/, where it fails every `path:` flake fetch of the tree.
      wrappedPackage = pkgs.symlinkJoin {
        name = "codegraph-wrapped";
        paths = [ cfg.package ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/codegraph \
            --set-default CODEGRAPH_TELEMETRY 0 \
            --set-default CODEGRAPH_NO_UPDATE_CHECK 1 \
            --set-default CODEGRAPH_NO_DAEMON 1
        '';
      };
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
        environment.systemPackages = [ wrappedPackage ];
      };
    };
}
