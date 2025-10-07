/*
  Package: claude-code
  Description: Anthropic's Claude Code CLI for repository-aware conversations and code generation.
  Homepage: https://docs.anthropic.com/en/docs/claude-code/overview
  Documentation: https://docs.anthropic.com/en/docs/claude-code/overview
  Repository: https://github.com/anthropics/claude-code

  Summary:
    * Provides a terminal client that connects to Claude for iterative coding, planning, and troubleshooting sessions.
    * Supports worktree context ingestion so Claude can read, diff, and suggest updates within git repositories.
    * Supports MCP (Model Context Protocol) servers for tool integrations.

  Options:
    claude-code login: Authenticate the CLI with an API key or OAuth flow.
    claude-code worktree --task <prompt>: Start an interactive session using local git state.
    claude-code mcp add <name> <command>: Add an MCP server.
    claude-code mcp list: List configured MCP servers.

  Example Usage:
    * `claude-code login` — Initiate authentication and store encrypted credentials locally.
    * `claude-code worktree --task "refactor telemetry collection"` — Ask Claude to propose git changes for a task.
    * `claude-code mcp add memory "npx -y @modelcontextprotocol/server-memory"` — Add the memory MCP server.
*/

{
  flake.homeManagerModules.apps.claude-code =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      cfg = config.programs.claude-code;

      # Helper to create Context7 wrapper if API key is available
      hasContext7Secret = config.sops.secrets ? "context7/api-key";
      context7Wrapper =
        if hasContext7Secret then
          pkgs.writeShellApplication {
            name = "context7-mcp";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.nodejs
            ];
            text = ''
              set -euo pipefail
              key_file="${config.sops.secrets."context7/api-key".path}"
              if [ ! -r "$key_file" ]; then
                echo "context7-mcp-wrapper: missing Context7 API key at $key_file" >&2
                exit 1
              fi
              api_key=$(tr -d '\n' < "$key_file")
              exec npx -y @upstash/context7-mcp --api-key "$api_key" "$@"
            '';
          }
        else
          null;

      # Context7 server configuration
      context7Server =
        if hasContext7Secret then
          {
            context7 = {
              command = "${context7Wrapper}/bin/context7-mcp";
              args = [ ];
              startup_timeout_ms = 60000;
            };
          }
        else
          { };

      # Default MCP servers configuration (matching codex)
      defaultMcpServers = {
        memory = {
          command = "npx";
          args = [
            "-y"
            "@modelcontextprotocol/server-memory"
          ];
          startup_timeout_ms = 60000;
        };
        sequential-thinking = {
          command = "npx";
          args = [
            "-y"
            "@modelcontextprotocol/server-sequential-thinking"
          ];
          startup_timeout_ms = 60000;
        };
        time = {
          command = "uvx";
          args = [ "mcp-server-time" ];
          startup_timeout_ms = 60000;
        };
        # Cloudflare MCP servers
        cfdocs = {
          command = "npx";
          args = [
            "mcp-remote"
            "https://docs.mcp.cloudflare.com/sse"
          ];
          startup_timeout_ms = 60000;
        };
        cfbuilds = {
          command = "npx";
          args = [
            "mcp-remote"
            "https://builds.mcp.cloudflare.com/sse"
          ];
          startup_timeout_ms = 60000;
        };
        cfobservability = {
          command = "npx";
          args = [
            "mcp-remote"
            "https://observability.mcp.cloudflare.com/sse"
          ];
          startup_timeout_ms = 60000;
        };
        cfradar = {
          command = "npx";
          args = [
            "mcp-remote"
            "https://radar.mcp.cloudflare.com/sse"
          ];
          startup_timeout_ms = 60000;
        };
        cfcontainers = {
          command = "npx";
          args = [
            "mcp-remote"
            "https://containers.mcp.cloudflare.com/sse"
          ];
          startup_timeout_ms = 60000;
        };
        cfbrowser = {
          command = "npx";
          args = [
            "mcp-remote"
            "https://browser.mcp.cloudflare.com/sse"
          ];
          startup_timeout_ms = 60000;
        };
        cfgraphql = {
          command = "npx";
          args = [
            "mcp-remote"
            "https://graphql.mcp.cloudflare.com/sse"
          ];
          startup_timeout_ms = 60000;
        };
        deepwiki = {
          command = "npx";
          args = [
            "mcp-remote"
            "https://mcp.deepwiki.com/mcp"
          ];
          startup_timeout_ms = 60000;
        };
      }
      // context7Server;

      # Merge user configuration with defaults
      mcpServers = lib.recursiveUpdate defaultMcpServers cfg.mcpServers;

      # Claude configuration file content
      claudeConfig = {
        mcpServers = mcpServers;
      }
      // cfg.settings;

    in
    {
      options.programs.claude-code = {
        enable = lib.mkEnableOption "Claude Code CLI";

        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.claude-code;
          description = "The Claude Code package to use";
        };

        settings = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          example = lib.literalExpression ''
            {
              autoUpdates = false;
              verbose = true;
              permissions = {
                allow = [ "Bash(uv:*)" ];
                deny = [ "Read(**/secrets/**)" ];
              };
            }
          '';
          description = ''
            Additional settings to merge into the Claude configuration file.
            These will be merged with the MCP servers configuration.
          '';
        };

        mcpServers = lib.mkOption {
          type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
          default = { };
          example = lib.literalExpression ''
            {
              my-server = {
                command = "python";
                args = [ "-m" "my_mcp_server" ];
                env = {
                  API_KEY = "secret";
                };
              };
            }
          '';
          description = ''
            MCP (Model Context Protocol) servers configuration.
            Each server entry should contain at minimum a `command` field,
            and optionally `args`, `env`, and other MCP server configuration.
            Extends the default set of servers (memory, sequential-thinking, time, Cloudflare suite, deepwiki, context7).
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        # Install the Claude Code package
        home.packages = [ cfg.package ];

        # Enable by default
        programs.claude-code.enable = lib.mkDefault true;

        # Create the Claude configuration file
        home.file.".claude.json" = lib.mkIf (mcpServers != { } || cfg.settings != { }) {
          text = builtins.toJSON claudeConfig;
        };
      };
    };
}
