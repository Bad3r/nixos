/*
  Upstream-shaped Claude Code defaults.

  Source of truth for default ~/.claude/settings.json keys and ~/.claude.json
  UI preferences. Values that depend on runtime evaluation (enabledPlugins,
  mcpServers) are injected by _settings.nix; this attrset only carries the
  static portion shared across hosts.
*/
{
  claudeSettingsBase = {
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
    outputStyle = "Proactive"; # Output style
    respectGitignore = false; # Respect .gitignore in file picker
    spinnerTipsEnabled = true; # Show tips
    terminalProgressBarEnabled = true; # Terminal progress bar
    useAutoModeDuringPlan = false; # Use auto mode during plan
  };

  # UI preferences for ~/.claude.json (merged with existing config in _settings.nix)
  claudeJsonConfigBase = {
    hasTrustDialogAccepted = true;
    hasCompletedProjectOnboarding = true;
    bypassPermissionsModeAccepted = true;
    autoCompactEnabled = true; # Auto-compact
    autocheckpointingEnabled = true; # Rewind code (checkpoints)
    autoConnectIde = false; # Auto-connect to IDE
    autoUpdates = false; # Auto-updates
    claudeInChromeDefaultEnabled = true; # Chrome enabled by default
    defaultToAgentsView = true; # Open agents view by default
    diffTool = "diff"; # Diff tool
    editorMode = "vim"; # Editor mode
    externalEditorContext = true; # Show last response in external editor
    preferredNotifChannel = "iterm2_with_bell"; # Notifications
    theme = "dark"; # Theme
    thinkingEnabled = true; # Thinking mode
    verbose = true; # Verbose output
  };
}
