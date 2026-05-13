/*
  Package: claude-code
  Description: Anthropic's Claude Code CLI for repository-aware conversations and code generation.
  Homepage: https://docs.anthropic.com/en/docs/claude-code/overview
  Documentation: https://docs.anthropic.com/en/docs/claude-code/overview
  Repository: https://github.com/anthropics/claude-code

  Notes:
    * MCP servers configured via flake.lib.agents.mcp (modules/agents/mcp.nix)
    * Agent skills configured via flake.lib.agents.skills (modules/agents/skills.nix)
    * Optional Context7 API key can be provisioned via SOPS at `sops.secrets."context7/api-key"`
    * Greptile plugin activation is optional and resolved during Home Manager
      activation only when the plugin is explicitly enabled.
    * LSP plugin enablement and binary installation are governed by
      programs.claude-code.extended.lspPlugins in modules/apps/claude-code.nix.
    * Additional non-LSP plugins are governed by
      programs.claude-code.extended.extraPlugins in modules/apps/claude-code.nix.
    * `enabledPlugins` keys end with `@<marketplace>` (see
      ~/.claude/plugins/known_marketplaces.json). Default plugins assume the
      `claude-plugins-official` marketplace is registered (install once with
      `claude-plugins install anthropics/claude-plugins-official`); entries
      that reference an unregistered marketplace are silently ignored.
    * Config is split across private helpers in modules/agents/claude-code/:
        _default-settings.nix  static defaults for settings.json and .claude.json
        _plugins.nix           enabledPlugins composition from osConfig
        _settings.nix          merges defaults + plugins + mcpServers
        _activation.nix        activation snippets (jq merge + optional bun install)
*/

_: {
  flake.homeManagerModules.apps."claude-code" =
    {
      config,
      osConfig,
      lib,
      pkgs,
      agents,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "claude-code" "extended" "enable" ] false osConfig;

      defaults = import ./_default-settings.nix;
      plugins = import ./_plugins.nix { inherit lib osConfig; };
      inherit (plugins) greptilePluginRequested;

      # MCP servers via compiled agents.mcp client profile
      mcpServers = agents.mcp.clients.claude.servers pkgs;

      settings = import ./_settings.nix {
        inherit pkgs defaults mcpServers;
        inherit (plugins) enabledPlugins;
      };

      greptileApiKeyPath = "${config.xdg.dataHome}/greptile/api-key";
      greptileHeadersHelperPath = "${config.home.homeDirectory}/.local/bin/claude-greptile-mcp-headers";

      activation = import ./_activation.nix {
        inherit
          lib
          pkgs
          osConfig
          config
          greptileApiKeyPath
          greptileHeadersHelperPath
          ;
        inherit (settings) claudeSettingsFile claudeJsonConfigFile;
        inherit (plugins) greptilePluginKey greptilePluginRequested;
      };

      bunInstallEnabled = lib.attrByPath [
        "programs"
        "claude-code"
        "extended"
        "installMethods"
        "bun"
        "enable"
      ] false osConfig;

      # ── Commit Skill ──────────────────────────────────────────────────────
      commitSkillMd = agents.skills.commit.claude;
    in
    {
      config = lib.mkIf nixosEnabled {
        home = {
          file = {
            ".claude/CLAUDE.md".source = ./CLAUDE.md;

            ".claude/skills/commit/SKILL.md" = {
              text = commitSkillMd;
            };
          }
          // lib.optionalAttrs greptilePluginRequested {
            ".local/bin/claude-greptile-mcp-headers" = {
              executable = true;
              text = ''
                #!${pkgs.bash}/bin/bash
                set -euo pipefail

                secret_path="''${GREPTILE_API_KEY_FILE:-${greptileApiKeyPath}}"
                if [ ! -r "$secret_path" ] || [ ! -s "$secret_path" ]; then
                  echo "GREPTILE_API_KEY file is not readable: $secret_path" >&2
                  exit 1
                fi

                secret_value="$(${pkgs.coreutils}/bin/tr -d '\r\n' < "$secret_path")"
                if [ -z "$secret_value" ]; then
                  echo "GREPTILE_API_KEY file is empty after normalization: $secret_path" >&2
                  exit 1
                fi

                ${pkgs.jq}/bin/jq -n --arg authorization "Bearer $secret_value" '{
                  Authorization: $authorization
                }'
              '';
            };
          }
          // lib.optionalAttrs bunInstallEnabled {
            ".local/bin/claude" = {
              executable = true;
              text = ''
                #!${pkgs.bash}/bin/bash
                set -euo pipefail

                ${lib.optionalString greptilePluginRequested ''
                  secret_path="''${GREPTILE_API_KEY_FILE:-${greptileApiKeyPath}}"
                  if [ -r "$secret_path" ] && [ -s "$secret_path" ]; then
                    if secret_value="$(${pkgs.coreutils}/bin/tr -d '\r\n' < "$secret_path")" && [ -n "$secret_value" ]; then
                      export GREPTILE_API_KEY="$secret_value"
                    fi
                  fi
                ''}

                bun_claude="$HOME/.local/share/bun/bin/claude"
                if [ -x "$bun_claude" ]; then
                  exec "$bun_claude" "$@"
                fi

                echo "ERROR: Claude Code bun install not found at $bun_claude" >&2
                exit 127
              '';
            };
          };

          inherit activation;

          sessionVariables = {
            # Duplicates of postFixup in modules/apps/claude-code.nix (belt-and-suspenders)
            DISABLE_AUTOUPDATER = "1";
            CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
            DISABLE_NON_ESSENTIAL_MODEL_CALLS = "1";
            DISABLE_TELEMETRY = "1";
            DISABLE_INSTALLATION_CHECKS = "1";
            # Runtime settings (not in postFixup)
            # ANTHROPIC_MODEL = defaultModel;
            CLAUDE_CODE_ENABLE_TELEMETRY = "0";
            DISABLE_ERROR_REPORTING = "1";
            CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR = "1";
            BASH_DEFAULT_TIMEOUT_MS = "240000";
            BASH_MAX_TIMEOUT_MS = "4800000";
            BASH_MAX_OUTPUT_LENGTH = "1024";
            # MAX_THINKING_TOKENS = "32768";
            # CLAUDE_CODE_MAX_OUTPUT_TOKENS = "UNKNOWN";
            # MAX_MCP_OUTPUT_TOKENS = "32000";
            CLAUDE_CODE_DISABLE_TERMINAL_TITLE = "0";
            CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL = "1";
            DISABLE_BUG_COMMAND = "1";
            USE_BUILTIN_RIPGREP = "0";
          };
        };
      };
    };
}
