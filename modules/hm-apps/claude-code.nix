/*
  Package: claude-code
  Description: Anthropic's Claude Code CLI for repository-aware conversations and code generation.
  Homepage: https://docs.anthropic.com/en/docs/claude-code/overview
  Documentation: https://docs.anthropic.com/en/docs/claude-code/overview
  Repository: https://github.com/anthropics/claude-code

  Notes:
    * Assumes Context7 API key is provisioned via SOPS at `sops.secrets."context7/api-key"`.
*/

_: {
  flake.homeManagerModules.apps."claude-code" =
    {
      osConfig,
      config,
      lib,
      pkgs,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "claude-code" "extended" "enable" ] false osConfig;

      # Check if context7 secret is available
      hasContext7Secret = config.sops.secrets ? "context7/api-key";

      mcp = import ../../lib/mcp-servers.nix {
        inherit lib pkgs config;
        defaultVariants = {
          deepwiki = "stdio";
        };
      };

      claudeMcpServers = mcp.select {
        sequential-thinking = true;
        time = false;
        cfdocs = true;
        cfbuilds = false;
        cfobservability = false;
        cfradar = false;
        cfcontainers = false;
        cfbrowser = true;
        cfgraphql = false;
        deepwiki = true;
        context7 = hasContext7Secret; # Only enable if secret exists
      };

      defaultServers = claudeMcpServers;

      # Claude Code settings.json configuration
      claudeSettings = {
        cleanupPeriodDays = 30;
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
        mcpServers = defaultServers;
      };

      # Combined config as JSON for the activation script
      claudeJsonConfigFile = pkgs.writeText "claude-json-config.json" (builtins.toJSON claudeJsonConfig);

    in
    {
      config = lib.mkIf nixosEnabled {
        home = {
          file.".claude/settings.json" = {
            text = builtins.toJSON claudeSettings;
            onChange = ''
              # Ensure Claude Code picks up the new settings
              echo "✢ Claude Code: settings updated"
            '';
          };

          # Configure Claude Code UI preferences and MCP servers in ~/.claude.json
          activation.claudeCodeSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            CLAUDE_CONFIG="$HOME/.claude.json"
            TMP_FILE="$(mktemp)"
            trap 'rm -f "$TMP_FILE"' EXIT

            # Ensure the file exists
            if [ ! -f "$CLAUDE_CONFIG" ]; then
              echo "{}" > "$CLAUDE_CONFIG"
            fi

            # Merge Nix-managed settings into existing config (preserves runtime state)
            if ! ${pkgs.jq}/bin/jq --slurpfile nixConfig ${claudeJsonConfigFile} \
              '. * $nixConfig[0]' "$CLAUDE_CONFIG" > "$TMP_FILE"; then
              echo "ERROR: jq failed to merge config" >&2
              exit 1
            fi

            # Validate result is valid JSON
            if ! ${pkgs.jq}/bin/jq empty "$TMP_FILE" 2>/dev/null; then
              echo "ERROR: resulting config is not valid JSON" >&2
              exit 1
            fi

            mv "$TMP_FILE" "$CLAUDE_CONFIG"
            chmod 600 "$CLAUDE_CONFIG"

            echo "✢ Claude Code: config applied"
          '';

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
            BASH_MAX_OUTPUT_LENGTH = "2048";
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
