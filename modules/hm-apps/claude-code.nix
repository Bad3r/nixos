/*
  Package: claude-code
  Description: Anthropic's Claude Code CLI for repository-aware conversations and code generation.
  Homepage: https://docs.anthropic.com/en/docs/claude-code/overview
  Documentation: https://docs.anthropic.com/en/docs/claude-code/overview
  Repository: https://github.com/anthropics/claude-code

  Notes:
    * MCP servers configured via flake.lib.mcp (modules/integrations/mcp-servers.nix)
    * Commit skill rules from flake.lib.skills (modules/integrations/skills.nix)
    * Context7 API key provisioned via SOPS at `sops.secrets."context7/api-key"`
*/

_: {
  flake.homeManagerModules.apps."claude-code" =
    {
      osConfig,
      lib,
      pkgs,
      mcpLib,
      skillsLib,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "claude-code" "extended" "enable" ] false osConfig;

      # MCP servers via centralized catalog
      mcpServers = mcpLib.mkServers pkgs [
        "sequential-thinking"
        "context7"
        "cfdocs"
        "cfbrowser"
        "deepwiki"
      ];

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
        inherit mcpServers;
      };

      # Combined config as JSON for the activation script
      claudeJsonConfigFile = pkgs.writeText "claude-json-config.json" (builtins.toJSON claudeJsonConfig);

      # ── Commit Skill ──────────────────────────────────────────────────────
      # Claude Code frontmatter + dynamic context + shared rules + workflow
      commitSkillMd = ''
        ---
        name: commit
        description: >
          This skill should be used when the user invokes /commit to create a git commit.
          It consolidates all project safety rules, Conventional Commits format, and staging
          best practices into a single repeatable workflow.
        disable-model-invocation: true
        allowed-tools: Bash(git status*), Bash(git diff*), Bash(git log*), Bash(git add *), Bash(git commit *), Read, Grep, Glob
        argument-hint: "[optional commit message]"
        ---

        # Git Commit Skill

        Create a well-formatted git commit following all project safety rules and Conventional Commits format.

        ## Current Git State

        Working tree status:
        !`git status --short`

        Already staged changes:
        !`git diff --staged --stat`

        Recent commits (for style reference):
        !`git log --oneline -5`

        ${skillsLib.commitRules}

        ### If `$ARGUMENTS` is provided

        Use the provided text as the commit message directly. Still run through the pre-commit checklist and staging rules before committing.

        ### If no arguments provided

        ${skillsLib.commitWorkflow}
      '';

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

          file.".claude/skills/commit/SKILL.md" = {
            text = commitSkillMd;
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

            echo "✢ Claude Code: config applied (MCP via mcp-servers-nix)"
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
