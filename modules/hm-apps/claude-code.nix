/*
  Package: claude-code
  Description: Anthropic's Claude Code CLI for repository-aware conversations and code generation.
  Homepage: https://docs.anthropic.com/en/docs/claude-code/overview
  Documentation: https://docs.anthropic.com/en/docs/claude-code/overview
  Repository: https://github.com/anthropics/claude-code

  Summary:
    * Provides a terminal client that connects to Claude for iterative coding, planning, and troubleshooting sessions.
    * Ships a sane default MCP toolbox (Context7, Brave Search, Cloudflare suite, DeepWiki, memory/time helpers).

  Notes:
    * Context7 and Brave Search entries expect SOPS secrets at `sops.secrets."context7/api-key"` and `sops.secrets."brave/api-key"`.
*/

{
  flake.homeManagerModules.apps."claude-code" =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      cfg = config.programs.claude-code;
      defaultTimeoutMs = 60000;

      hasSecret = name: lib.hasAttrByPath [ name ] config.sops.secrets;
      getSecret = name: lib.getAttrFromPath [ name ] config.sops.secrets;

      context7Secret = if hasSecret "context7/api-key" then getSecret "context7/api-key" else null;
      context7Wrapper =
        if context7Secret != null && context7Secret ? path then
          pkgs.writeShellApplication {
            name = "context7-mcp";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.nodejs
            ];
            text = ''
              set -euo pipefail
              key_file="${context7Secret.path}"
              if [ ! -r "$key_file" ]; then
                echo "context7-mcp: missing Context7 API key at $key_file" >&2
                exit 1
              fi
              api_key=$(tr -d '\n' < "$key_file")
              exec npx -y @upstash/context7-mcp --api-key "$api_key" "$@"
            '';
          }
        else
          null;

      braveSecret = if hasSecret "brave/api-key" then getSecret "brave/api-key" else null;
      braveWrapper =
        if braveSecret != null && braveSecret ? path then
          pkgs.writeShellApplication {
            name = "brave-search-mcp";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.nodejs
            ];
            text = ''
              set -euo pipefail
              key_file="${braveSecret.path}"
              if [ ! -r "$key_file" ]; then
                echo "brave-search-mcp: missing Brave API key at $key_file" >&2
                exit 1
              fi
              export BRAVE_API_KEY="$(tr -d '\n' < "$key_file")"
              exec npx -y @modelcontextprotocol/server-brave-search "$@"
            '';
          }
        else
          null;

      baseServers = {
        memory = {
          type = "stdio";
          command = "npx";
          args = [
            "-y"
            "@modelcontextprotocol/server-memory"
          ];
          startup_timeout_ms = defaultTimeoutMs;
        };
        sequential-thinking = {
          type = "stdio";
          command = "npx";
          args = [
            "-y"
            "@modelcontextprotocol/server-sequential-thinking"
          ];
          startup_timeout_ms = defaultTimeoutMs;
        };
        time = {
          type = "stdio";
          command = "uvx";
          args = [ "mcp-server-time" ];
          startup_timeout_ms = defaultTimeoutMs;
        };
        cfdocs = {
          type = "stdio";
          command = "npx";
          args = [
            "mcp-remote"
            "https://docs.mcp.cloudflare.com/sse"
          ];
          startup_timeout_ms = defaultTimeoutMs;
        };
        cfbuilds = {
          type = "stdio";
          command = "npx";
          args = [
            "mcp-remote"
            "https://builds.mcp.cloudflare.com/sse"
          ];
          startup_timeout_ms = defaultTimeoutMs;
        };
        cfobservability = {
          type = "stdio";
          command = "npx";
          args = [
            "mcp-remote"
            "https://observability.mcp.cloudflare.com/sse"
          ];
          startup_timeout_ms = defaultTimeoutMs;
        };
        cfradar = {
          type = "stdio";
          command = "npx";
          args = [
            "mcp-remote"
            "https://radar.mcp.cloudflare.com/sse"
          ];
          startup_timeout_ms = defaultTimeoutMs;
        };
        cfcontainers = {
          type = "stdio";
          command = "npx";
          args = [
            "mcp-remote"
            "https://containers.mcp.cloudflare.com/sse"
          ];
          startup_timeout_ms = defaultTimeoutMs;
        };
        cfbrowser = {
          type = "stdio";
          command = "npx";
          args = [
            "mcp-remote"
            "https://browser.mcp.cloudflare.com/sse"
          ];
          startup_timeout_ms = defaultTimeoutMs;
        };
        cfgraphql = {
          type = "stdio";
          command = "npx";
          args = [
            "mcp-remote"
            "https://graphql.mcp.cloudflare.com/sse"
          ];
          startup_timeout_ms = defaultTimeoutMs;
        };
        deepwiki = {
          type = "http";
          url = "https://mcp.deepwiki.com/mcp";
          startup_timeout_ms = defaultTimeoutMs;
        };
      };

      context7Server = lib.optionalAttrs (context7Wrapper != null) {
        context7 = {
          type = "stdio";
          command = "${context7Wrapper}/bin/context7-mcp";
          args = [ ];
          startup_timeout_ms = defaultTimeoutMs;
        };
      };

      braveServer = lib.optionalAttrs (braveWrapper != null) {
        brave-search = {
          type = "stdio";
          command = "${braveWrapper}/bin/brave-search-mcp";
          args = [ ];
          startup_timeout_ms = defaultTimeoutMs;
        };
      };

      defaultServers = baseServers // context7Server // braveServer;

      defaultConfigFile = pkgs.writeText "claude-code-default-config.json" (
        builtins.toJSON {
          verbose = true;
          preferredNotifChannel = "iterm2_with_bell";
          editorMode = "vim";
          supervisorMode = true;
          autocheckpointingEnabled = true;
          autoUpdates = false;
          autoCompactEnabled = true;
          diffTool = "kdiff";
          mcpServers = defaultServers;
        }
      );
    in
    {
      config = {
        programs.claude-code = lib.mkIf cfg.enable {
          package = lib.mkDefault pkgs.claude-code;
          mcpServers = lib.mkOptionDefault defaultServers;
        };

        home.sessionVariables = lib.mkIf cfg.enable {
          ANTHROPIC_MODEL = "opus";
          DISABLE_AUTOUPDATER = "1";
          CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
          DISABLE_TELEMETRY = "1";
          CLAUDE_CODE_ENABLE_TELEMETRY = "0";
          DISABLE_ERROR_REPORTING = "1";
          DISABLE_NON_ESSENTIAL_MODEL_CALLS = "1";
          CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR = "1";
          CLAUDE_BASH_DEFAULT_TIMEOUT_MS = "240000";
          CLAUDE_BASH_MAX_TIMEOUT_MS = "4800000";
          BASH_MAX_OUTPUT_LENGTH = "1024";
          MAX_THINKING_TOKENS = "32768";
          CLAUDE_CODE_MAX_OUTPUT_TOKENS = "1";
          MAX_MCP_OUTPUT_TOKENS = "32000";
          cleanupPeriodDays = "30";
        };

        home.activation.claudeCodeMcpDefaults = lib.mkIf cfg.enable (
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            CLAUDE_CFG="${lib.escapeShellArg (config.home.homeDirectory + "/.claude.json")}"
            TMP="$(mktemp)"
            mkdir -p "$(dirname "$CLAUDE_CFG")"
            if [ -f "$CLAUDE_CFG" ]; then
              ${pkgs.jq}/bin/jq --slurpfile defaults ${defaultConfigFile} '
                ($defaults[0]) as $d
                | .mcpServers = (
                    ($d.mcpServers // {}) as $defaultsM
                    | (.mcpServers // {}) as $existing
                    | reduce ($defaultsM | to_entries[]) as $entry ($existing;
                        if has($entry.key) then . else . + {($entry.key): $entry.value} end
                      )
                  )
                | .verbose = (.verbose // $d.verbose)
                | .preferredNotifChannel = (.preferredNotifChannel // $d.preferredNotifChannel)
                | .editorMode = (.editorMode // $d.editorMode)
                | .supervisorMode = (.supervisorMode // $d.supervisorMode)
                | .autocheckpointingEnabled = (.autocheckpointingEnabled // $d.autocheckpointingEnabled)
                | .autoUpdates = (.autoUpdates // $d.autoUpdates)
                | .autoCompactEnabled = (.autoCompactEnabled // $d.autoCompactEnabled)
                | .diffTool = (.diffTool // $d.diffTool)
              ' "$CLAUDE_CFG" > "$TMP"
            else
              cp ${defaultConfigFile} "$TMP"
            fi
            mv "$TMP" "$CLAUDE_CFG"
          ''
        );

        warnings =
          lib.optional (cfg.enable && context7Wrapper == null && hasSecret "context7/api-key") ''
            programs.claude-code: Context7 secret detected but wrapper could not be created (missing path?).
          ''
          ++ lib.optional (cfg.enable && braveWrapper == null && hasSecret "brave/api-key") ''
            programs.claude-code: Brave Search secret detected but wrapper could not be created (missing path?).
          '';
      };
    };
}
