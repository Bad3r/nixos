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
    * Greptile plugin activation is resolved during Home Manager activation
      from the SOPS-managed runtime API key file.
    * LSP plugin enablement and binary installation are governed by
      programs.claude-code.extended.lspPlugins in modules/apps/claude-code.nix.
    * Additional non-LSP plugins are governed by
      programs.claude-code.extended.extraPlugins in modules/apps/claude-code.nix.
    * `enabledPlugins` keys end with `@<marketplace>` (see
      ~/.claude/plugins/known_marketplaces.json). Default plugins assume the
      `claude-plugins-official` marketplace is registered (install once with
      `claude-plugins install anthropics/claude-plugins-official`); entries
      that reference an unregistered marketplace are silently ignored.
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

      bunInstallEnabled = lib.attrByPath [
        "programs"
        "claude-code"
        "extended"
        "installMethods"
        "bun"
        "enable"
      ] false osConfig;
      bunInstallDir = "${config.xdg.dataHome}/bun";
      bunBin = lib.getExe osConfig.programs.bun.extended.package;

      # MCP servers via compiled agents.mcp client profile
      mcpServers = agents.mcp.clients.claude.servers pkgs;

      greptilePluginKey = "greptile@claude-plugins-official";
      greptileApiKeyPath = "${config.xdg.dataHome}/greptile/api-key";
      greptileHeadersHelperPath = "${config.home.homeDirectory}/.local/bin/claude-greptile-mcp-headers";
      greptilePluginRequested = lib.attrByPath [
        "programs"
        "claude-code"
        "extended"
        "extraPlugins"
        greptilePluginKey
      ] false osConfig;
      greptilePluginRequestedShell = if greptilePluginRequested then "1" else "0";
      nixInstallEnabled = lib.attrByPath [
        "programs"
        "claude-code"
        "extended"
        "installMethods"
        "nix"
        "enable"
      ] false osConfig;

      extraPlugins = lib.attrByPath [ "programs" "claude-code" "extended" "extraPlugins" ] { } osConfig;
      gatedExtraPlugins =
        extraPlugins
        // lib.optionalAttrs (builtins.hasAttr greptilePluginKey extraPlugins) {
          ${greptilePluginKey} = false;
        };

      # enabledPlugins is composed of:
      #   1. LSP plugins derived from programs.claude-code.extended.lspPlugins
      #      (single source of truth for LSP-style plugins).
      #   2. Additional plugins from programs.claude-code.extended.extraPlugins,
      #      keyed by the "<plugin>@<marketplace>" identifier used by
      #      Claude Code's settings.json. Greptile is forced off in the base
      #      JSON and re-enabled by the activation script only when its
      #      SOPS-managed runtime API key file is readable.
      enabledPlugins =
        (lib.mapAttrs' (
          pluginKey: enabled: lib.nameValuePair "${pluginKey}@claude-plugins-official" enabled
        ) (lib.attrByPath [ "programs" "claude-code" "extended" "lspPlugins" ] { } osConfig))
        // gatedExtraPlugins;

      # Claude Code settings.json configuration
      claudeSettings = {
        cleanupPeriodDays = 30;
        inherit enabledPlugins;
        env = {
          # Duplicates of postFixup in modules/apps/claude-code.nix (belt-and-suspenders)
          DISABLE_AUTOUPDATER = "1";
          CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
          DISABLE_NON_ESSENTIAL_MODEL_CALLS = "1";
          DISABLE_TELEMETRY = "1";
          DISABLE_INSTALLATION_CHECKS = "1";
          # Runtime settings (not in postFixup)
          CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR = "1";
          BASH_DEFAULT_TIMEOUT_MS = "240000";
          BASH_MAX_TIMEOUT_MS = "4800000";
          # MAX_THINKING_TOKENS = "32768";
        };
        includeCoAuthoredBy = false;
        permissions = {
          allow = [
            "Read(~/.claude/CLAUDE.md)"
            "Read(../../.claude/CLAUDE.md)"
            "Read(../../../.claude/CLAUDE.md)"
            "WebFetch(domain:docs.anthropic.com)"
            "WebFetch(domain:*.github.com)"
            "Bash(find :*)"
            "Bash(xargs :*)"
            "Bash(sort :*)"
            "Bash(uniq :*)"
            "Bash(pytest :*)"
            "Bash(grep :*)"
            "Bash(head :*)"
            "Bash(pkill :*)"
            "Bash(tee :*)"
            "Bash(bash :*)"
            "Bash(ls :*)"
            "Bash(biome :*)"
            "Bash(curl :*)"
            "Bash(diff :*)"
            "Bash(patch :*)"
            "Bash(touch :*)"
            "Bash(cp :*)"
            "Bash(pwd :*)"
            "Bash(mkdir :*)"
            "Bash(cut :*)"
            "Bash(awk :*)"
            "Bash(cat :*)"
            "Bash(cd :*)"
            "Bash(coverage :*)"
            "Bash(echo :*)"
            "Bash(fd :*)"
            "Bash(git :*)"
            "Bash(jq :*)"
            "Bash(make :*)"
            "Bash(npm run :*)"
            "Bash(nvim :*)"
            "Bash(python :*)"
            "Bash(pyright :*)"
            "Bash(rg :*)"
            "Bash(ruff :*)"
            "Bash(sed :*)"
            "Bash(source :*)"
            "Bash(tail :*)"
            "Bash(time :*)"
            "Bash(timeout :*)"
            "Bash(uv :*)"
            "Bash(wc :*)"
            "Bash(zsh :*)"
            "Read(**)"
            "Write(**)"
            "Edit(**)"
          ];
          deny = [ ];
          defaultMode = "plan";
        };
        # model = defaultModel; # Model (leave unset for default)
        alwaysThinkingEnabled = true;
        enableAllProjectMcpServers = true;
        language = "en"; # Language
        outputStyle = "default"; # Output style
        respectGitignore = true; # Respect .gitignore in file picker
        spinnerTipsEnabled = true; # Show tips
        terminalProgressBarEnabled = true; # Terminal progress bar
      };

      # UI preferences for ~/.claude.json (merged with existing config)
      claudeJsonConfig = {
        hasTrustDialogAccepted = true;
        hasCompletedProjectOnboarding = true;
        bypassPermissionsModeAccepted = true;
        autoCompactEnabled = true; # Auto-compact
        autocheckpointingEnabled = true; # Rewind code (checkpoints)
        autoConnectIde = false; # Auto-connect to IDE
        autoUpdates = false; # Auto-updates
        claudeInChromeDefaultEnabled = false; # Chrome enabled by default
        diffTool = "diff"; # Diff tool
        editorMode = "vim"; # Editor mode
        preferredNotifChannel = "iterm2_with_bell"; # Notifications
        theme = "dark"; # Theme
        thinkingEnabled = true; # Thinking mode
        verbose = true; # Verbose output
        inherit mcpServers;
      };

      # Combined config as JSON for the activation script
      claudeSettingsFile = pkgs.writeText "claude-settings.json" (builtins.toJSON claudeSettings);
      claudeJsonConfigFile = pkgs.writeText "claude-json-config.json" (builtins.toJSON claudeJsonConfig);

      # ── Commit Skill ──────────────────────────────────────────────────────
      commitSkillMd = agents.skills.commit.claude;

    in
    {
      config = lib.mkIf nixosEnabled {
        home = {
          file = {
            ".claude/CLAUDE.md".source = ./claude-code/CLAUDE.md;

            ".claude/skills/commit/SKILL.md" = {
              text = commitSkillMd;
            };

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
          // lib.optionalAttrs (!nixInstallEnabled) {
            ".local/bin/claude" = {
              executable = true;
              text = ''
                #!${pkgs.bash}/bin/bash
                set -euo pipefail

                secret_path="''${GREPTILE_API_KEY_FILE:-${greptileApiKeyPath}}"
                if [ -r "$secret_path" ] && [ -s "$secret_path" ]; then
                  if secret_value="$(${pkgs.coreutils}/bin/tr -d '\r\n' < "$secret_path")" && [ -n "$secret_value" ]; then
                    export GREPTILE_API_KEY="$secret_value"
                  fi
                fi

                bun_claude="$HOME/.local/share/bun/bin/claude"
                if [ -x "$bun_claude" ]; then
                  exec "$bun_claude" "$@"
                fi

                echo "ERROR: Claude Code bun install not found at $bun_claude" >&2
                exit 127
              '';
            };
          };

          # Configure Claude Code UI preferences and MCP servers in ~/.claude.json
          activation = {
            claudeCodeSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              CLAUDE_SETTINGS="$HOME/.claude/settings.json"
              CLAUDE_SETTINGS_TMP="$(mktemp)"
              CLAUDE_CONFIG="$HOME/.claude.json"
              CLAUDE_CONFIG_TMP="$(mktemp)"
              trap 'rm -f "$CLAUDE_SETTINGS_TMP" "$CLAUDE_CONFIG_TMP"' EXIT

              mkdir -p "$HOME/.claude"

              if [ -r "$CLAUDE_SETTINGS" ]; then
                existing_settings="$CLAUDE_SETTINGS"
              else
                existing_settings="${pkgs.writeText "empty-json.json" "{}"}"
              fi

              if [ "${greptilePluginRequestedShell}" = "1" ] && [ -r "${greptileApiKeyPath}" ] && [ -s "${greptileApiKeyPath}" ]; then
                greptile_enabled=true
              else
                greptile_enabled=false
              fi

              if ! ${pkgs.jq}/bin/jq \
                --slurpfile nixSettings ${claudeSettingsFile} \
                --arg plugin "${greptilePluginKey}" \
                --argjson greptileEnabled "$greptile_enabled" \
                '. as $existing
                | $nixSettings[0] as $nix
                | ($existing * $nix)
                | .enabledPlugins = (($existing.enabledPlugins // {}) + ($nix.enabledPlugins // {}))
                | .enabledPlugins[$plugin] = $greptileEnabled
                | .env = ((($existing.env // {}) + ($nix.env // {})) | del(.GREPTILE_API_KEY))' \
                "$existing_settings" > "$CLAUDE_SETTINGS_TMP"; then
                echo "ERROR: jq failed to merge Claude Code settings" >&2
                exit 1
              fi

              if ! ${pkgs.jq}/bin/jq empty "$CLAUDE_SETTINGS_TMP" 2>/dev/null; then
                echo "ERROR: resulting Claude Code settings are not valid JSON" >&2
                exit 1
              fi

              mv "$CLAUDE_SETTINGS_TMP" "$CLAUDE_SETTINGS"
              chmod 600 "$CLAUDE_SETTINGS"

              for greptile_mcp_config in \
                "$HOME"/.claude/plugins/cache/claude-plugins-official/greptile/*/.mcp.json \
                "$HOME"/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/greptile/.mcp.json
              do
                [ -f "$greptile_mcp_config" ] || continue
                GREPTILE_MCP_TMP="$(mktemp)"
                if ! ${pkgs.jq}/bin/jq --arg helper "${greptileHeadersHelperPath}" \
                  '.greptile.headersHelper = $helper | del(.greptile.headers)' \
                  "$greptile_mcp_config" > "$GREPTILE_MCP_TMP"; then
                  echo "ERROR: jq failed to patch Greptile MCP config: $greptile_mcp_config" >&2
                  exit 1
                fi
                mv "$GREPTILE_MCP_TMP" "$greptile_mcp_config"
                chmod 644 "$greptile_mcp_config"
              done

              # Ensure the file exists
              if [ ! -f "$CLAUDE_CONFIG" ]; then
                echo "{}" > "$CLAUDE_CONFIG"
              fi

              # Merge Nix-managed settings into existing config while replacing
              # Nix-managed MCP server entries wholesale to avoid stale per-server
              # keys like old command/args transport fallbacks lingering forever.
              if ! ${pkgs.jq}/bin/jq --slurpfile nixConfig ${claudeJsonConfigFile} \
                '. as $existing
                | $nixConfig[0] as $nix
                | ($existing * $nix)
                | .mcpServers = (($existing.mcpServers // {}) + ($nix.mcpServers // {}))' \
                "$CLAUDE_CONFIG" > "$CLAUDE_CONFIG_TMP"; then
                echo "ERROR: jq failed to merge config" >&2
                exit 1
              fi

              # Validate result is valid JSON
              if ! ${pkgs.jq}/bin/jq empty "$CLAUDE_CONFIG_TMP" 2>/dev/null; then
                echo "ERROR: resulting config is not valid JSON" >&2
                exit 1
              fi

              mv "$CLAUDE_CONFIG_TMP" "$CLAUDE_CONFIG"
              chmod 600 "$CLAUDE_CONFIG"

              echo "✢ Claude Code: config applied (MCP via agents.mcp)"
            '';
          }
          // lib.optionalAttrs bunInstallEnabled {
            # The probe URL is pinned to the public npm registry because every
            # host in this repo runs bun against the default registry. If a
            # future host points bun at a private mirror via `~/.bunfig.toml`
            # or `BUN_CONFIG_REGISTRY`, this probe will check the wrong
            # endpoint and either skip a working install or run an install
            # that fails immediately. Update the URL alongside the bun config
            # if that ever happens.
            installClaudeCodeViaBun = lib.hm.dag.entryAfter [ "writeBoundary" "createBunDir" ] ''
              export BUN_INSTALL="${bunInstallDir}"
              if ${pkgs.curl}/bin/curl --silent --show-error --fail --max-time 5 \
                  --output /dev/null \
                  https://registry.npmjs.org/@anthropic-ai/claude-code/latest; then
                run ${bunBin} install -g @anthropic-ai/claude-code
              elif [ -x "$BUN_INSTALL/bin/claude" ]; then
                echo "warning: installClaudeCodeViaBun: npm registry probe failed (see curl error above), keeping existing install at $BUN_INSTALL/bin/claude" >&2
              else
                echo "warning: installClaudeCodeViaBun: npm registry probe failed (see curl error above) and no existing claude-code binary at $BUN_INSTALL/bin/claude; rerun home-manager switch once the registry is reachable" >&2
              fi
            '';
          };

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
