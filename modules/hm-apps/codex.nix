{
  flake.homeManagerModules.apps.codex =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
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
    in
    {
      programs.codex = {
        enable = true;
        package = null;
        settings = {
          # TODO: Wire the Context7 API key via nix-sops once secret management is available.
          show_raw_agent_reasoning = true;
          experimental_use_exec_command_tool = false;
          sandbox_mode = "danger-full-access";
          model = "gpt-5-codex";
          approval_policy = "never";
          profile = "gpt-5-codex";
          shell_environment_policy = {
            "inherit" = "all";
            ignore_default_excludes = true;
            exclude = [
              "AWS_*"
              "AZURE_*"
            ];
          };
          tui = {
            notifications = true;
          };
          tools = {
            web_search = true;
          };
          mcp_servers = context7Server // {
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
            # Cloudflare MCP servers – https://github.com/cloudflare/mcp-server-cloudflare#cloudflare-mcp-server
            cfdocs = {
              command = "npx";
              args = [
                "mcp-remote"
                "https://docs.mcp.cloudflare.com/sse"
              ];
              startup_timeout_ms = 60000;
            };
            cfbindings = {
              command = "npx";
              args = [
                "mcp-remote"
                "https://bindings.mcp.cloudflare.com/sse"
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
          };
          profiles = {
            gpt-5-codex = {
              model = "gpt-5-codex";
              approval_policy = "never";
              model_supports_reasoning_summaries = true;
              model_reasoning_effort = "high";
              model_reasoning_summary = "detailed";
              model_verbosity = "high";
            };
          };
        };
        custom-instructions = "";
      };

      home.packages = [ pkgs.codex ];
      home.sessionVariables.CODEX_HOME = lib.mkDefault "${config.xdg.configHome}/codex";
    };
}
