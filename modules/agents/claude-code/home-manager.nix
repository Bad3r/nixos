/*
  Package: claude-code
  Description: Anthropic's Claude Code CLI for repository-aware conversations and code generation.
  Homepage: https://docs.anthropic.com/en/docs/claude-code/overview
  Documentation: https://docs.anthropic.com/en/docs/claude-code/overview
  Repository: https://github.com/anthropics/claude-code

  Notes:
    * MCP servers configured via flake.lib.agents.mcp (modules/agents/mcp.nix)
    * Agent skills configured via flake.lib.agents.skills (modules/agents/skills.nix)
    * User-level instructions generated via flake.lib.agents.systemPrompt
      (modules/agents/system-prompt.nix)
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
        _wrapper.nix           shell launcher environment and binary selection
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
      claudePkg = lib.attrByPath [
        "programs"
        "claude-code"
        "extended"
        "package"
      ] pkgs.claude-code osConfig;
      installMethods = lib.attrByPath [ "programs" "claude-code" "extended" "installMethods" ] {
        nix.enable = false;
        bun.enable = false;
      } osConfig;

      defaults = import ./_default-settings.nix;
      claudeEnv = import ./_env.nix;
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
      bunInstallDir = "${config.xdg.dataHome}/bun";
      configuredExternalBinary = lib.attrByPath [
        "programs"
        "claude-code"
        "extended"
        "externalBinary"
      ] null osConfig;
      externalBinary =
        if configuredExternalBinary == null then
          "${bunInstallDir}/bin/claude"
        else
          configuredExternalBinary;

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

      claudeRuntime = import ./_wrapper.nix {
        inherit
          lib
          pkgs
          claudePkg
          bunInstallDir
          externalBinary
          installMethods
          greptilePluginRequested
          greptileApiKeyPath
          ;
      };

      # ── Commit Skill ──────────────────────────────────────────────────────
      claudeInstructions = agents.systemPrompt.render {
        vars.questionTool = "AskUserQuestion";
      };
      commitSkillMd = agents.skills.commit.claude;
    in
    {
      config = lib.mkIf nixosEnabled {
        home = {
          file = {
            ".claude/CLAUDE.md".text = claudeInstructions;

            ".claude/skills/commit/SKILL.md" = {
              text = commitSkillMd;
            };

            ".local/bin/claude" = {
              source = lib.getExe claudeRuntime.claudeWrapped;
              executable = true;
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
          };

          inherit activation;

          # bun puts its global bin on home.sessionPath; mkBefore orders
          # ~/.local/bin ahead of it so the wrapper shadows a bun-global claude.
          sessionPath = lib.mkBefore [ "${config.home.homeDirectory}/.local/bin" ];

          # Full env from the shared source (modules/agents/claude-code/_env.nix);
          # belt-and-suspenders with the binary postFixup and settings.json `env`.
          sessionVariables = claudeEnv.all;
        };
      };
    };
}
