{
  flake.homeManagerModules.apps."claude-code" =
    { ... }:
    {
      home.file.".claude/settings.json" = {
        text = builtins.toJSON {
          alwaysThinkingEnabled = true;
          model = "opus";
          # Include co-authored-by Claude in git commits
          includeCoAuthoredBy = true;
          # Retention period for local chat transcripts
          cleanupPeriodDays = 30;
          # Custom status line context
          statusLine = {
            gitStatus = true;
            gitBranch = true;
            workingDirectory = true;
          };
          # Additional settings can be added here
          # See: https://docs.claude.com/en/docs/claude-code/settings
        };
        onChange = ''
          # Ensure Claude Code picks up the new settings
          echo "Claude Code settings updated"
        '';
      };
    };
}
